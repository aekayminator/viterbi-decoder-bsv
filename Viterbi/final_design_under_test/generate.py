import struct
import random
import math
import sys

# --- SETTINGS ---
# Change these values to generate different test cases
N_STATES = 2
M_OBSERVATIONS = 2
NUM_SEQUENCES = 20
MIN_SEQ_LEN = 1
MAX_SEQ_LEN = 2
# --- END SETTINGS ---


def float32_to_hex32(f_val):
    """Converts a Python float to its 32-bit IEEE 754 hex string (Big Endian)."""
    # This puts the sign bit at the beginning of the hex string.
    return struct.pack('>f', f_val).hex()

def normalize_log(probs):
    """
    Takes a list of positive numbers, normalizes them to sum to 1,
    and returns a list of their natural logarithms.
    Ensures log probs are never 0.0 or -inf.
    """
    total = sum(probs)
    if total == 0:
        log_prob = -1e9 # Large negative number, not -inf
        if probs:
            log_prob = math.log(1.0 / len(probs)) if len(probs) > 1 else math.log(1.0 - 1e-7)
        return [log_prob] * len(probs)
    
    if len(probs) == 1:
        return [math.log(1.0 - 1e-7)] 

    log_probs = []
    for p in probs:
        if p <= 0:
            log_probs.append(-1e9) # Large negative, not -inf
        else:
            norm_p = p / total
            if norm_p >= 1.0: # Safeguard
                norm_p = 1.0 - 1e-7
            log_probs.append(math.log(norm_p))
    return log_probs

def write_n_dat_text(filename, N, M):
    """Writes N.dat as text (hex)"""
    with open(filename, 'w', encoding='utf-8') as f:
        # --- CHANGE: Write as hex ---
        f.write(f"{N:x}\n")
        f.write(f"{M:x}\n")
    print(f"Wrote {filename} (N={N:x}, M={M:x}) (text/hex format)")

def write_a_dat_text(filename, N):
    """Writes a random A.dat as text (hex)"""
    with open(filename, 'w', encoding='utf-8') as f:
        q0_probs = [random.random() + 1e-9 for _ in range(N)]
        log_q0_probs = normalize_log(q0_probs)
        
        if any(p >= 0 for p in log_q0_probs):
            print(f"Error: A.dat generator (q0) produced a non-negative value (>= 0). Aborting.")
            sys.exit(1)
            
        for p in log_q0_probs:
            f.write(f"{float32_to_hex32(p)}\n")
            
        for _ in range(N):
            probs = [random.random() + 1e-9 for _ in range(N)]
            log_probs = normalize_log(probs)

            if any(p >= 0 for p in log_probs):
                print(f"Error: A.dat generator (q1..qN) produced a non-negative value (>= 0). Aborting.")
                sys.exit(1)
                
            for p in log_probs:
                f.write(f"{float32_to_hex32(p)}\n")
    print(f"Wrote {filename} (({N+1} x {N}) random matrix) (text/hex format)")

def write_b_dat_text(filename, N, M):
    """Writes a random B.dat as text (hex)"""
    with open(filename, 'w', encoding='utf-8') as f:
        for _ in range(N):
            probs = [random.random() + 1e-9 for _ in range(M)]
            log_probs = normalize_log(probs)

            if any(p >= 0 for p in log_probs):
                print(f"Error: B.dat generator produced a non-negative value (>= 0). Aborting.")
                sys.exit(1)
                
            for p in log_probs:
                f.write(f"{float32_to_hex32(p)}\n")
    print(f"Wrote {filename} ({N} x {M} random matrix) (text/hex format)")

def write_input_dat_text(filename, M, num_seqs, min_len, max_len):
    """Writes a random input.dat as text (hex)"""
    count = 0
    with open(filename, 'w', encoding='utf-8') as f:
        for _ in range(num_seqs):
            T = random.randint(min_len, max_len)
            count += 1
            for _ in range(T):
                obs = random.randint(1, M)
                # --- CHANGE: Write as hex ---
                f.write(f"{obs:x}\n")
            
            f.write("ffffffff\n") # This is already hex
            
        f.write("0\n") # This is also valid hex
    print(f"Wrote {filename} ({count} sequences, len {min_len}-{max_len}, text/hex format)")


# --- Main execution ---
# This code now runs directly, using the settings from the top of the file.
if __name__ == "__main__":
    print("--- Generating Random Test Data (Text Format) ---")
    
    # Use settings from the top of the file
    N = N_STATES
    M = M_OBSERVATIONS
    
    # Check constraints
    if (N + 1) * N > 1024:
        print(f"Error: (N+1)*N = {((N+1)*N)} > 1024. Max N is 31.")
        sys.exit(1)
    if N * M > 1024:
        print(f"Error: N*M = {(N*M)} > 1024. Reduce N or M.")
        sys.exit(1)
        
    if MIN_SEQ_LEN > MAX_SEQ_LEN:
        print("Error: MIN_SEQ_LEN cannot be greater than MAX_SEQ_LEN.")
        sys.exit(1)
        
    # Generate the files
    write_n_dat_text("N.dat", N, M)
    write_a_dat_text("A.dat", N)
    write_b_dat_text("B.dat", N, M)
    write_input_dat_text(
        "input.dat", 
        M, 
        NUM_SEQUENCES, 
        MIN_SEQ_LEN, 
        MAX_SEQ_LEN
    )
    print("--- Random Data Generation Complete ---")