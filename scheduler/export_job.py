#!/usr/bin/env python
import os
import subprocess
import shutil
from datetime import datetime
import pandas as pd

# Configure paths
DBT_PATH = "/app/dbt"
EXPORT_DIR = "/data/exports"
TASKS_CSV = "tasks_daily.csv"

# Create export directory if it doesn't exist
os.makedirs(EXPORT_DIR, exist_ok=True)

# Set timestamp for this export
timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
print(f"Starting task export job at {timestamp}")

# Change to DBT directory and run DBT
os.chdir(DBT_PATH)
print("Running DBT export models...")
try:
    # Run DBT export models
    result = subprocess.run(
        ["dbt", "run", "--select", "exports.*"],
        check=True,
        capture_output=True,
        text=True
    )
    print(f"DBT run output: {result.stdout}")
except subprocess.CalledProcessError as e:
    print(f"Error running DBT: {e}")
    print(f"Error output: {e.stderr}")
    exit(1)

# Create timestamped copies of the export files
for file_name in [TASKS_CSV]:
    src = os.path.join(EXPORT_DIR, file_name)
    if os.path.exists(src):
        # Create timestamped backup
        backup = os.path.join(EXPORT_DIR, f"{file_name.split('.')[0]}_{timestamp}.csv")
        shutil.copy2(src, backup)
        print(f"Created backup at {backup}")

        # Process the file to add additional data if needed
        try:
            df = pd.read_csv(src)
            # You could add any additional processing here

            # Save the processed data back to the original file
            df.to_csv(src, index=False)
            print(f"Processed {file_name}")
        except Exception as e:
            print(f"Error processing {file_name}: {e}")
    else:
        print(f"Warning: Export file {src} not found")

print(f"Task export job completed at {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
