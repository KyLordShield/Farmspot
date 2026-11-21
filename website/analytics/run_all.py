import subprocess

STEPS = [
    ("Step 1 - Pull raw data", "python", "step1_connect_and_pull.py"),
    ("Step 2 - Compute Insights", "python", "step2_compute_insights.py"),
    ("Step 3 - Save to Databse", "python", "step3_save_to_db.py"),
]

def run_pipepline():
    for label, *command in STEPS:
        print("=" * 40)
        print(f"Running: {label}")
        print("=" * 40)

        result = subprocess.run(command, capture_output=True, text=True)

        if result.stdout:
            print(result.stdout)
        if result.stderr:
            print(result.stderr)
        
        if result.returncode != 0:
            print(f"!! {label} FAILED: Stopping pipeline.")
            return False
    
    else:
        print("All steps completed successfully.")
        return True

if __name__ == "__main__":
    run_pipepline()