
# Pipelined Viterbi Decoder in BSV

## 1. Overview

This project is a high-performance, pipelined Viterbi decoder implemented in Bluespec SystemVerilog (BSV). The design is memory-agnostic, holding only $O(N)$ internal state and streaming all large traceback tables from external memory.

It implements the Viterbi algorithm in the log-probability domain, using the `min-sum` recurrence to maintain numerical stability. The core's microarchitecture is a streaming, deeply pipelined design, featuring a custom, 2-stage pipelined IEEE-754 FP32 adder to achieve a high clock frequency.

The design was rigorously verified using a comprehensive Python-based test harness. This environment automates a loop of generating randomized test cases (varying $N$, $M$, and sequence length), checking the BSV simulation output against a bit-accurate golden Python model, and logging the results. This automated flow was supplemented by manual, targeted testing for corner cases in the FP32 adder and the $N<5$ RAW hazard.

---


### 2. Individual Contributions

**Akshith (EE22B008)**
* Architected the full, pipelined streaming design, targeting an area-optimized, bubble-free flow that hides traceback latency.
* Implemented the baseline BSV DUT and testbench; ran initial synthesis to identify PPA bottlenecks.
* Refactored the design to move all large memory external, cutting power/area.
* Finalized the implementation with dynamic scratch-pad usage and output-overwrite to remove scaling dependencies and tune PPA.

**Venkat (EE22B015)**
* Designed, implemented, and unit-tested the 2-stage pipelined FP32 adder, including a rigorous testbench for subnormals, overflows, and rounding.
* Built the complete system-level Python verification environment (golden model, test generator, automation script).
* Debugged the design, identifying and fixing critical bugs (like the $N<5$ RAW hazard).
* Authored all project documentation (LaTeX report and `README.md`).
---

## 3. Compilation and Execution Instructions

This project is organized into separate directories for the main design, the standalone adder, and the verification scripts.

### 3.1. Final Viterbi Project (BSV Simulation)

This is the main, integrated design.

* **Directory:** `final/`
* **Source Files:**
    * `mkdut.bsv` (Top-level Viterbi DUT)
    * `FPadder32Pipelined.bsv` (The 2-stage FP32 adder)
    * `testviterbi.bsv` (The BSV testbench)
    * `Makefile`

* **To Compile and Run Simulation:**
    ```bash
    cd final
    make b_sim
    ```

### 3.2. Standalone FP32 Adder

This directory contains the unit-level testbench for the `FPadder32Pipelined` module.


* **Directory:** `final/`
* **Source Files:**
    * `mkTb.bsv` (Top-level Viterbi DUT)
    * `FPadder32Pipelined.bsv` (The 2-stage FP32 adder)
    * `Makefile`

* **To Compile and Run Simulation:**
    ```bash
    cd final
    make b_sim
    ```

### 3.3. Python Verification Environment

This directory contains the automated, system-level verification suite.

---

# BSV Automated Verification Harness

This project contains a Python-based verification harness for testing a BSV hardware design against a Python "golden model".

It supports two workflows:

1.  **Automated Random Verification:** (Recommended) Runs 100s of tests with randomized parameters (`N`, `M`, etc.) to find bugs.
2.  **Manual Single-Test Workflow:** (For Debugging) Allows you to run a single, specific test case by running each script manually.

## Workflow 1: Automated Random Verification (Primary)

This is the main orchestrator script that runs a complete, randomized regression test.

### File Overview

* `verification_script.py`: The main orchestrator. You run this file.
* `generate_test_data.py`: A Python **module** that is *imported* by the orchestrator to generate test files.
* `golden_model.py`: Your Python-based solver. This is called by the orchestrator.
* `make b_sim` (Your Task): The command that runs your BSV simulation.

### How to Use This Setup


#### Step 1: Customize `verification_script.py`

Open `verification_script.py` and edit the **`--- CONFIGURATION ---`** section:

1.  `NUM_TESTS`: Set how many *randomized batches* you want to run (e.g., 100).
2.  `--- RANDOM PARAMETER RANGES ---` section to change the randomization constraints for $N$, $M$, their product, and sequence counts/lengths.
3.  `BSV_SIM_COMMAND`: Set this to the command that runs your simulation. It is currently set to `["make", "b_sim"]`.
4.  `BSV_SIM_TIMEOUT_SECONDS`: Set the max time (in seconds) to wait for your simulation to complete. The default is `300` (5 minutes).


#### Step 2: Run the Verification

1.  Make sure your BSV executable is ready (e.g., your `Makefile` is set up).
2.  Make sure all three Python files (`verification_script.py`, `generate_test_data.py`, `golden_model.py`) are in the same directory.
3.  Run the main script from your terminal:
    ```bash
    python verification_script.py
    ```
4.  The script will print `PASSED` or `FAILED` for each *batch test*.
5.  When it's done, open `verification.log` to see the detailed results, including the `N`, `M`, and `Num-Sequences` used for every test.

## Workflow 2: Manual Single-Test Workflow (for Debugging)

Use this workflow when a test fails in the automated run, and you want to re-run that *specific* test case manually.

For example, if the log says a test failed with `N=5`, `M=10`, `Num_Sequences=3`, you can use this process to debug it.

### How to Use This Setup

#### Step 1: Manually Configure `generate_test_data.py`

1.  Open `generate_test_data.py`.
2.  Scroll to the **very bottom** of the file to the `if __name__ == "__main__":` block.
3.  Edit the `N_debug`, `M_debug`, `Num_Seq_debug`, etc. variables to match the *specific test case* you want to run.
    ```python
    # This block is for running this file standalone for debugging
    if __name__ == "__main__":
        print("--- Running generate_test_data.py standalone for debug ---")
    
        # --- EDIT THESE VALUES ---
        N_debug = 5
        M_debug = 10
        Num_Seq_debug = 3
        Min_Len_debug = 1
        Max_Len_debug = 20
        # --- END EDIT ---
    
        try:
            generate_all_test_data(...)
    ```

#### Step 2: Run Scripts Manually (One by One)

Run these commands in your terminal in this order:

1.  **Generate Data:** This creates `A.dat`, `B.dat`, `N.dat`, and `input.dat` using the `_debug` values you just set.
    ```bash
    python generate_test_data.py
    ```
2.  **Run Golden Model:** This reads the `.dat` files and creates `expected_output.dat`.
    ```bash
    python golden_model.py
    ```
3.  **Run BSV Simulation:** This reads the `.dat` files and creates `actual_output.dat`.
    ```bash
    make b_sim
    ```

#### Step 3: Check Results

You can now manually inspect the files:

* Open `expected_output.dat` and `actual_output.dat` in a text editor and compare them.
* This also allows you to open `input.dat` and all other files to see the *exact* data that caused the failure, which is essential for debugging your hardware.

---

## 4. Maximum Clock Frequency

Based on synthesis with the final pipelined adder and memory-out architecture:

* **Maximum Clock Frequency:** **357 MHz**
* **Minimum Clock Period:** **2.8 ns**
