"""
viterbi_decoder.py

Usage: put N.dat, A.dat, B.dat, Input.dat in the same directory and run:
    python viterbi_decoder.py

Writes Output.dat.

Assumptions & formats:
- N.dat : two integers (N and M) as text (one per line) OR two 32-bit ints in binary.
- A.dat : (N+1)*N IEEE-754 float32 words (binary) OR whitespace/line hex/dec values.
    Order: first N words = transitions from start q0 -> q1..qN (a0j),
           remaining N*N words = a_ij in row-major with i=1..N, j=1..N.
- B.dat : N*M IEEE-754 float32 words in order b1(o1)..b1(oM), b2(o1)..bN(oM).
- Input.dat: sequence of 32-bit integers (binary or text). Sequences separated by 0xFFFFFFFF.
    File ends with 0xFFFFFFFF followed by 0x0.
- Output.dat: for each input sequence, write the most probable state (one per line),
    then the log-probability as IEEE-754 float32 hex (8 lowercase hex digits), then ffffffff.
    Final file ends with a line containing 0.
"""

import struct
import os
import sys
from typing import List, Tuple
import numpy as np

# ---- helpers for flexible reading ----

def try_read_all_as_binary_words(path: str) -> List[int]:
    """Read file as sequence of 32-bit words (unsigned ints) in little-endian if possible."""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) % 4 != 0:
        raise ValueError("Binary length is not multiple of 4")
    return list(struct.unpack("<" + "I" * (len(data) // 4), data))

def try_read_all_as_binary_floats(path: str) -> List[float]:
    with open(path, "rb") as f:
        data = f.read()
    if len(data) % 4 != 0:
        raise ValueError("Binary length is not multiple of 4")
    return list(struct.unpack("<" + "f" * (len(data) // 4), data))

def parse_text_words(path: str) -> List[str]:
    """Return whitespace-separated tokens from text file."""
    with open(path, "r", encoding="utf-8") as f:
        return f.read().split()

def parse_token_as_int(tok: str) -> int:
    tok = tok.strip()
    if tok.lower().startswith("0x"):
        return int(tok, 16)
    try:
        return int(tok, 16)
    except Exception:
        return int(tok, 10)

def parse_token_as_float_from_hex_or_dec(tok: str) -> float:
    tok = tok.strip()
    if tok.lower().startswith("0x"):
        ui = int(tok, 16)
        return struct.unpack("<f", struct.pack("<I", ui))[0]
    try:
        ui = int(tok, 16)
        return struct.unpack("<f", struct.pack("<I", ui))[0]
    except Exception:
        return float(tok)

# ---- reading specific files ----

def read_N_file(path: str) -> Tuple[int, int]:
    try:
        words = try_read_all_as_binary_words(path)
        if len(words) >= 2:
            return int(words[0]), int(words[1])
    except Exception:
        pass
    toks = parse_text_words(path)
    if len(toks) < 2:
        raise RuntimeError(f"Could not parse N/M from {path}")
    return int(parse_token_as_int(toks[0])), int(parse_token_as_int(toks[1]))

def read_A_file(path: str, N: int) -> Tuple[np.ndarray, np.ndarray]:
    floats = None
    try:
        floats = try_read_all_as_binary_floats(path)
    except Exception:
        pass
    if floats is None or len(floats) != (N + 1) * N:
        toks = parse_text_words(path)
        if len(toks) != (N + 1) * N:
            try:
                words = try_read_all_as_binary_words(path)
                if len(words) == (N + 1) * N:
                    floats = [struct.unpack("<f", struct.pack("<I", w))[0] for w in words]
                else:
                    if len(toks) >= (N + 1) * N:
                        floats = [parse_token_as_float_from_hex_or_dec(t) for t in toks[: (N + 1) * N]]
                    else:
                        raise RuntimeError(f"A.dat doesn't have expected {(N + 1) * N} entries (found {len(toks)})")
            except Exception as e:
                raise RuntimeError(f"Unable to parse {path}: {e}")
        else:
            floats = [parse_token_as_float_from_hex_or_dec(t) for t in toks]

    arr = np.array(floats, dtype=np.float32)
    A_start = arr[:N].astype(np.float32)
    A_trans = arr[N:].reshape((N, N)).astype(np.float32)
    return A_start, A_trans

def read_B_file(path: str, N: int, M: int) -> np.ndarray:
    floats = None
    try:
        floats = try_read_all_as_binary_floats(path)
    except Exception:
        pass
    if floats is None or len(floats) != N * M:
        toks = parse_text_words(path)
        if len(toks) != N * M:
            try:
                words = try_read_all_as_binary_words(path)
                if len(words) == N * M:
                    floats = [struct.unpack("<f", struct.pack("<I", w))[0] for w in words]
                else:
                    if len(toks) >= N * M:
                        floats = [parse_token_as_float_from_hex_or_dec(t) for t in toks[: N * M]]
                    else:
                        raise RuntimeError(f"B.dat doesn't have expected {N * M} entries (found {len(toks)})")
            except Exception as e:
                raise RuntimeError(f"Unable to parse {path}: {e}")
        else:
            floats = [parse_token_as_float_from_hex_or_dec(t) for t in toks]

    return np.array(floats, dtype=np.float32).reshape((N, M))

def read_input_file(path: str) -> List[List[int]]:
    seqs: List[List[int]] = []
    try:
        toks = parse_text_words(path)
        ints = [parse_token_as_int(t) for t in toks]
        cur, i = [], 0
        while i < len(ints):
            w = ints[i]; i += 1
            if w == 0xFFFFFFFF:
                if i < len(ints) and ints[i] == 0:
                    if cur:
                        seqs.append(cur.copy())
                    cur = []
                    break
                else:
                    if cur: # Don't append empty lists if there are consecutive ffff...
                        seqs.append(cur.copy())
                    cur = []
            else:
                cur.append(int(w))
        # Add this check to fix the *other* bug (see below)
        if cur:
             seqs.append(cur)
        return seqs
    except Exception as e:
        raise RuntimeError(f"Failed to parse input.dat as text: {e}")

# ---- Viterbi algorithm ----

def run_viterbi_for_sequence(obs: List[int], N: int, M: int,
                             A_start: np.ndarray, A_trans: np.ndarray, B: np.ndarray) -> Tuple[List[int], float]:
    if len(obs) == 0:
        return [], float("-inf")
    oidx = [o - 1 for o in obs]
    T = len(oidx)
    V = np.full((T, N), -np.inf, dtype=np.float32)
    B = B.astype(np.float32)
    A_trans = A_trans.astype(np.float32)
    A_start = A_start.astype(np.float32)

    for j in range(N):
        V[0, j] = A_start[j] + B[j, oidx[0]]

    backp = np.zeros((T, N), dtype=np.int32)
    for t in range(1, T):
        ot = oidx[t]
        emis_col = B[:, ot]
        prev = V[t - 1, :]
        cand = (prev[:, None] + A_trans)
        best_prev_indices = np.argmax(cand, axis=0)
        best_values = cand[best_prev_indices, np.arange(N)]
        V[t, :] = best_values + emis_col
        backp[t, :] = best_prev_indices

    best_last = int(np.argmax(V[-1, :]))
    best_logprob = float(V[-1, best_last])
    path = [0] * T
    cur = best_last
    for t in range(T - 1, -1, -1):
        path[t] = cur + 1
        if t > 0:
            cur = int(backp[t, cur])
    return path, best_logprob

# ---- utilities for output formatting ----

def float32_to_hex32(f: float) -> str:
    b = struct.pack("<f", np.float32(f).item())
    ui = struct.unpack("<I", b)[0]
    return f"{ui:08x}"

# ---- main flow ----

def main():
    fn_N = "N.dat"
    fn_A = "A.dat"
    fn_B = "B.dat"
    fn_input = "input.dat"
    fn_output = "output_p.dat"

    for fn in (fn_N, fn_A, fn_B, fn_input):
        if not os.path.exists(fn):
            print(f"Error: required file '{fn}' not found.", file=sys.stderr)
            return

    N, M = read_N_file(fn_N)
    if N <= 0 or M <= 0:
        raise RuntimeError("Invalid N or M")

    A_start, A_trans = read_A_file(fn_A, N)
    B = read_B_file(fn_B, N, M)
    sequences = read_input_file(fn_input)

    outputs = []
    for seq in sequences:
        for v in seq:
            if not (1 <= v <= M):
                raise RuntimeError(f"Observation value {v} outside 1..{M}")

        path, lp = run_viterbi_for_sequence(seq, N, M, A_start, A_trans, B)
        outputs.append((path, lp))

    with open(fn_output, "w", encoding="utf-8") as f:
        for path, lp in outputs:
            for st in path:
                f.write(f"{st:08x}\n")
            f.write(f"{float32_to_hex32(lp)}\n")
            f.write("ffffffff\n")
        f.write("00000000\n")

    print(f"Wrote {fn_output} with {len(outputs)} sequences.")

if __name__ == "__main__":
    main()
