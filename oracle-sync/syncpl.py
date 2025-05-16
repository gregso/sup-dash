#!/usr/bin/env python3
import os
import logging
import time
import sys
from datetime import datetime
import oracledb
import clickhouse_driver
import polars as pl
from dotenv import load_dotenv

# Basic logging setup
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger("sync")

# Load environment variables
load_dotenv()

def sync_oracle_to_clickhouse():
    """Synchronize data from Oracle to ClickHouse using polars with complete schema control"""

    # Get database configurations from environment
    oracle_user = os.getenv('ORACLE_USER')
    oracle_password = os.getenv('ORACLE_SYNC_PASSWORD')
    oracle_host = os.getenv('ORACLE_HOST')
    oracle_port = os.getenv('ORACLE_PORT', '1521')
    oracle_service = os.getenv('ORACLE_SERVICE')

    clickhouse_host = os.getenv('CLICKHOUSE_HOST', 'clickhouse')
    clickhouse_user = os.getenv('CLICKHOUSE_USER', 'default')
    clickhouse_password = os.getenv('CLICKHOUSE_PASSWORD', 'default')
    clickhouse_db = os.getenv('CLICKHOUSE_DB', 'support_analytics')

    try:
        # Connect to ClickHouse
        logger.info(f"Connecting to ClickHouse at {clickhouse_host}")
        clickhouse = clickhouse_driver.Client(
            host=clickhouse_host,
            user=clickhouse_user,
            password=clickhouse_password,
            database=clickhouse_db,
            settings={'use_numpy': False}
        )

        # Get last synced ID
        try:
            result = clickhouse.execute(f"SELECT MAX(act_aa_id) FROM {clickhouse_db}.support_tasks")
            last_id = result[0][0] if result[0][0] else 0
        except Exception as e:
            logger.warning(f"Error getting last sync ID: {e}, defaulting to 0")
            last_id = 0

        logger.info(f"Last synced ID: {last_id}")

        # Connect to Oracle
        logger.info(f"Connecting to Oracle at {oracle_host}:{oracle_port}/{oracle_service}")
        dsn = f"{oracle_host}:{oracle_port}/{oracle_service}"

        with oracledb.connect(user=oracle_user, password=oracle_password, dsn=dsn) as oracle_conn:
            cursor = oracle_conn.cursor()

            # Query for data newer than the last synced ID
            query = """
            SELECT
                sta.AA_ID AS ACT_AA_ID,
                stt.TASK_ID, stt.CLIENT, stt.STATUS12, stt.CREATEDDATETIME,
                steiv."GROUP", steiv.COMPANY, steiv."POSITION", steiv.JOB_CLASSIFICATION, steiv.EMAIL,
                steiv.DEPT_DESCR, steiv.DIV_DESCR,
                stt.LIVEISSUE, stt.TASK_CLASS,
                sta.PR_AC_SORT, sta.VIEWYN, sta.ACTDATETIME, sta.ACTIONCODE12, sta.ACTEMPL,
                sta.ASSIGNEDTO, sta.TMS_TASK_ID AS TASK_AA_ID, stt.PRODUCT
            FROM SDRR_TMS_ACTIONS sta
            JOIN SDRR_TMS_TASKS stt ON stt.AA_ID = sta.TMS_TASK_ID
            LEFT JOIN SDRR_TMS_EMPLOYEE_INFO_VIEW steiv ON sta.ACTEMPL = steiv.EMPID
            WHERE sta.AA_ID > :last_id AND sta.ACTDATETIME >= TRUNC(SYSDATE - 3*360)
            ORDER BY sta.AA_ID
            """

            logger.info("Executing Oracle query")
            cursor.execute(query, [last_id])
            columns = [col[0].lower() for col in cursor.description]

            # Process data in batches
            batch_size = 5000
            total_records = 0

            while True:
                rows = cursor.fetchmany(batch_size)
                if not rows:
                    break

                logger.info(f"Processing batch of {len(rows)} records")

                # APPROACH: Convert rows to dictionary first, then construct dataframe
                # This bypasses Polars' schema inference completely

                # Convert Oracle rows to list of dictionaries with explicit type handling
                dict_records = []
                for row in rows:
                    record = {}
                    for i, col in enumerate(columns):
                        value = row[i]

                        # Handle specific column types
                        if col == 'pr_ac_sort':
                            record[col] = int(value) if value is not None else 0
                        elif col in ['createddatetime', 'actdatetime']:
                            # Keep datetime objects as they are
                            record[col] = value
                        else:
                            # Ensure all other fields are strings
                            record[col] = str(value) if value is not None else ""

                    dict_records.append(record)

                # Insert into ClickHouse directly using the dictionary records
                # This bypasses Polars completely for this case
                try:
                    logger.info(f"Inserting {len(dict_records)} records into ClickHouse")
                    clickhouse.execute(
                        f"INSERT INTO {clickhouse_db}.support_tasks ({', '.join(columns)}) VALUES",
                        dict_records
                    )
                    total_records += len(dict_records)
                    logger.info(f"Successfully inserted batch, total: {total_records}")
                except Exception as e:
                    logger.error(f"Error inserting batch into ClickHouse: {e}")
                    if dict_records:
                        logger.error(f"Sample record: {dict_records[0]}")
                        logger.error(f"Types: {[(k, type(v)) for k, v in dict_records[0].items()]}")
                    raise

            logger.info(f"Sync completed successfully. Total records: {total_records}")
            return total_records

    except Exception as e:
        logger.error(f"Sync failed: {e}")
        import traceback
        logger.error(traceback.format_exc())
        return 0

def main():
    """Main loop function for periodic sync"""
    while True:
        try:
            logger.info("Starting Oracle to ClickHouse synchronization")
            records_synced = sync_oracle_to_clickhouse()
            logger.info(f"Sync completed: {records_synced} records processed")
        except Exception as e:
            logger.error(f"Sync process encountered an error: {e}")

        # Sleep before next sync if running in container
        if os.environ.get('DOCKER_CONTAINER'):
            logger.info("Waiting for next sync interval...")
            time.sleep(3600)  # 1 hour
        else:
            break

if __name__ == "__main__":
    main()
