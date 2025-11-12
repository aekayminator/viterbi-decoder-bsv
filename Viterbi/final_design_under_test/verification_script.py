import subprocess
import os
import datetime
import logging
import random
import sys

# --- CONFIGURATION (You MUST edit this section) ---

# 1. Set the number of *randomized batch tests* to run
NUM_TESTS = 100

# 2. Set the path to your compiled BSV simulation executable
#    *** This sim MUST read A.dat, B.dat, N.dat, input.dat
#    *** and write its results to 'actual_output.dat'
# BSV_SIM_EXECUTABLE = "./bsv_simulation"  # <--- !!! CUSTOMIZE ME !!!
#
# --- NEW ---
# Set the command to run your simulation.
# If your command is "make b_sim", this is correct:
BSV_SIM_COMMAND = ["make", "b_sim"]
# If your command is just running an executable, set it like this:
# BSV_SIM_COMMAND = ["./bsv_simulation"]
# --- END NEW ---

# --- NEW TIMEOUT SETTING ---
# Set the maximum time (in seconds) to wait for the BSV sim to complete
# before marking it as "timed out".
BSV_SIM_TIMEOUT_SECONDS = 300 # (Default is 5 minutes)
# --- END NEW ---


# 3. Set the name of your Python interpreter
PYTHON_INTERPRETER = "python" # or "python3"

# 4. Define the script names
#    We now import the generator, so this is only for the golden model
import generate_test_data
GOLDEN_MODEL_SCRIPT = "golden_viterbi.py"

# 5. Define the output files
#    Golden model MUST write to this file
EXPECTED_OUTPUT_FILE = "output_p.dat"
#    BSV sim MUST write to this file
ACTUAL_OUTPUT_FILE = "output.dat"

# 6. Log file name
LOG_FILE = "verification.log"

# --- RANDOM PARAMETER RANGES (Customize me) ---
# 0 < N_STATES < 32  (1 to 31)
MIN_N_STATES = 1
MAX_N_STATES = 31

# 0 < M_OBSERVATIONS < 512 (1 to 511)
MIN_M_OBS = 1
MAX_M_OBS = 511

# M_OBSERVATIONS * N_STATES < 1024
MAX_PRODUCT = 1023 # (Must be < 1024)

# 1 < NUM_SEQUENCES < 10 (2 to 9)
MIN_NUM_SEQ = 2
MAX_NUM_SEQ = 9

# Constants
MIN_SEQ_LEN = 1
MAX_SEQ_LEN = 20
# --- End of Configuration ---


# Setup logging
# ... (logging setup code is unchanged) ...
logging.basicConfig(
    filename=LOG_FILE,
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filemode='w'  # 'w' = overwrite log each run
)
console = logging.StreamHandler()
console.setLevel(logging.INFO)
formatter = logging.Formatter('%(message)s')
console.setFormatter(formatter)
logging.getLogger('').addHandler(console)

def run_script(script_name, interpreter):
# ... (this function is unchanged) ...
    """Runs a Python script as a subprocess and checks for errors."""
    try:
        command = [interpreter, script_name]
        result = subprocess.run(command, 
                                capture_output=True, 
                                text=True, 
                                timeout=30)
                                
        if result.returncode != 0:
            logging.error(f"Script '{script_name}' FAILED")
            logging.error(f"Stdout: {result.stdout}")
            logging.error(f"Stderr: {result.stderr}")
            return False
        
        logging.debug(f"Script '{script_name}' ran successfully.")
        logging.debug(f"Stdout: {result.stdout}")
        return True
    except Exception as e:
        logging.error(f"Failed to run script '{script_name}': {e}")
        return False

def run_bsv_simulation():
# ... (this function is unchanged) ...
    command = BSV_SIM_COMMAND # <-- New
    
    try:
        result = subprocess.run(command, 
                                capture_output=True, 
                                text=True, 
                                timeout=BSV_SIM_TIMEOUT_SECONDS) # 60-second timeout <-- MODIFIED
                                
        if result.returncode != 0:
            # logging.error(f"BSV Sim '{BSV_SIM_EXECUTABLE}' FAILED (crashed)") <-- Old
            logging.error(f"BSV Sim command '{' '.join(command)}' FAILED (crashed)") # <-- New
            logging.error(f"Stderr: {result.stderr}")
            return False
        
        if not os.path.exists(ACTUAL_OUTPUT_FILE):
            # logging.error(f"BSV Sim '{BSV_SIM_EXECUTABLE}' FAILED (did not create {ACTUAL_OUTPUT_FILE})") <-- Old
            logging.error(f"BSV Sim command '{' '.join(command)}' FAILED (did not create {ACTUAL_OUTPUT_FILE})") # <-- New
            return False

        # logging.debug(f"BSV Sim '{BSV_SIM_EXECUTABLE}' ran successfully.") <-- Old
        logging.debug(f"BSV Sim command '{' '.join(command)}' ran successfully.") # <-- New
        return True
        
    except FileNotFoundError:
        # logging.error(f"Executable not found: {BSV_SIM_EXECUTABLE}") <-- Old
        logging.error(f"Command not found: {command[0]}. Is 'make' (or your executable) in your PATH?") # <-- New
        return False
    except subprocess.TimeoutExpired:
        # logging.error(f"BSV Sim '{BSV_SIM_EXECUTABLE}' timed out.") <-- Old
        logging.error(f"BSV Sim command '{' '.join(command)}' timed out (exceeded {BSV_SIM_TIMEOUT_SECONDS}s).") # <-- New
        return False
    except Exception as e:
        # logging.error(f"BSV Sim '{BSV_SIM_EXECUTABLE}' failed: {e}") <-- Old
        logging.error(f"BSV Sim command '{' '.join(command)}' failed: {e}") # <-- New
        return False

def compare_output_files():
# ... (this function is unchanged) ...
    """
    Compares the expected and actual output files.
    Returns True on match, False on mismatch or error.
    """
    try:
        with open(EXPECTED_OUTPUT_FILE, 'r') as f:
            expected_content = f.read().strip()
            
        with open(ACTUAL_OUTPUT_FILE, 'r') as f:
            actual_content = f.read().strip()
            
        if expected_content == actual_content:
            logging.debug("Output files match.")
            return True
        else:
            logging.error("!!! OUTPUT MISMATCH !!!")
            logging.error(f"Expected:\n{expected_content}")
            logging.error(f"Actual:\n{actual_content}")
            return False
            
    except FileNotFoundError as e:
        logging.error(f"Output file not found during comparison: {e}")
        return False
    except Exception as e:
        logging.error(f"Error during file comparison: {e}")
        return False

def generate_constrained_parameters():
    """
    Generates random N, M, and Num_Sequences that
    respect the defined constraints.
    """
    # Pick N first
    N = random.randint(MIN_N_STATES, MAX_N_STATES)
    
    # Now calculate valid range for M
    # M must be <= MAX_M_OBS
    # M must be <= MAX_PRODUCT / N
    max_m_allowed = min(MAX_M_OBS, MAX_PRODUCT // N)
    
    if max_m_allowed < MIN_M_OBS:
        # This can happen if N is large (e.g., N=31, max_m = 1023//31 = 33)
        # But if MIN_M_OBS was, say, 50, this would fail.
        # In our case, MIN_M_OBS=1, so this check is just a safeguard.
        logging.warning(f"Could not find valid M for N={N}. Retrying.")
        # We'll just pick a new N
        N = random.randint(MIN_N_STATES, max(MIN_N_STATES, MAX_PRODUCT // MIN_M_OBS))
        max_m_allowed = min(MAX_M_OBS, MAX_PRODUCT // N)
        
    M = random.randint(MIN_M_OBS, max_m_allowed)
    
    # Pick number of sequences
    Num_Seq = random.randint(MIN_NUM_SEQ, MAX_NUM_SEQ)
    
    return N, M, Num_Seq
    
def main():
    logging.info(f"--- Verification Run Started ---")
    # ... (logging info unchanged) ...
    logging.info(f"Timestamp: {datetime.datetime.now()}")
    logging.info(f"Total Batch Tests: {NUM_TESTS}")
    # logging.info(f"BSV Executable: {BSV_SIM_EXECUTABLE}") <-- Old
    logging.info(f"BSV Sim Command: {' '.join(BSV_SIM_COMMAND)}") # <-- New
    logging.info("="*50 + "\n")
    
    passed_count = 0
    total_run_actual = 0
    
    for i in range(NUM_TESTS):
        test_num = i + 1
        total_run_actual = test_num
        logging.info(f"--- Running Test Batch {test_num}/{NUM_TESTS} ---")
        
        # 1. Generate random parameters for this run
        try:
            N, M, Num_Seq = generate_constrained_parameters()
            logging.info(f"Parameters: N={N}, M={M}, Num_Sequences={Num_Seq}")
        except Exception as e:
            logging.error(f"Failed to generate parameters: {e}")
            logging.info(f"Test {test_num}/{NUM_TESTS}: FAILED (Parameter Generation)\n")
            break # Critical failure
            
        # 2. Generate test data files using the module
        try:
            generate_test_data.generate_all_test_data(
                N, M, Num_Seq, MIN_SEQ_LEN, MAX_SEQ_LEN
            )
            logging.debug("Test data files generated.")
        except Exception as e:
            logging.error(f"generate_test_data.py failed: {e}")
            logging.info(f"Test {test_num}/{NUM_TESTS}: FAILED (Data Generation)")
            logging.info("Stopping run due to error.\n")
            break # Critical failure
        
        # 3. Run golden model (as a script)
        if not run_script(GOLDEN_MODEL_SCRIPT, PYTHON_INTERPRETER):
            logging.info(f"Test {test_num}/{NUM_TESTS}: FAILED (Golden Model Run)")
            logging.info("Stopping run due to error.\n")
            break # Critical failure
            
        # 4. Run BSV simulation
        if not run_bsv_simulation():
            logging.info(f"Test {test_num}/{NUM_TESTS}: FAILED (BSV Simulation Run)")
            logging.info("See log for crash details.\n")
            continue # Non-critical, try next test
            
        # 5. Compare outputs
        if compare_output_files():
            passed_count += 1
            logging.info(f"Test {test_num}/{NUM_TESTS}: PASSED\n")
        else:
            logging.info(f"Test {test_num}/{NUM_TESTS}: FAILED (Output Mismatch)\n")
        
        logging.debug("-"*50)

    # 6. Final Summary
    logging.info("\n" + "="*50)
    # ... (final summary logic is updated slightly) ...
    logging.info("--- Verification Finished ---")
    
    failed_count = total_run_actual - passed_count
    
    logging.info(f"Total Tests Run: {total_run_actual}")
    logging.info(f"Passed: {passed_count}")
    logging.info(f"Failed: {failed_count}")
    
    if total_run_actual > 0:
        pass_rate = (passed_count / total_run_actual) * 100
        logging.info(f"Pass Rate: {pass_rate:.2f}%")
        
    logging.info("="*50)
    logging.info(f"Full log available at: {LOG_FILE}")

if __name__ == "__main__":
    main()