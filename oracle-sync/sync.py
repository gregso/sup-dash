#!/usr/bin/env python3
import os
import logging
import time
import sys
from datetime import datetime, timedelta
import pandas as pd
import oracledb  # Changed from cx_Oracle to oracledb
import clickhouse_driver
from dotenv import load_dotenv

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('oracle_sync')

# Load environment variables
load_dotenv()

# Database configuration
ORACLE_USER = os.getenv('ORACLE_USER')
ORACLE_SYNC_PASSWORD = os.getenv('ORACLE_SYNC_PASSWORD')
ORACLE_HOST = os.getenv('ORACLE_HOST')
ORACLE_PORT = os.getenv('ORACLE_PORT', '1521')
ORACLE_SERVICE = os.getenv('ORACLE_SERVICE')
ORACLE_DSN = os.getenv('ORACLE_DSN') or f"{ORACLE_HOST}:{ORACLE_PORT}/{ORACLE_SERVICE}"

CLICKHOUSE_HOST = os.getenv('CLICKHOUSE_HOST', 'clickhouse')
CLICKHOUSE_USER = os.getenv('CLICKHOUSE_USER', 'default')
CLICKHOUSE_PASSWORD = os.getenv('CLICKHOUSE_PASSWORD', '')
CLICKHOUSE_DB = os.getenv('CLICKHOUSE_DB', 'support_analytics')

# Set Oracle environment variables
os.environ['NLS_LANG'] = 'AMERICAN_AMERICA.AL32UTF8'

def get_oracle_connection():
    """Establish connection to Oracle database"""
    try:
        # Initialize oracle client (only needed in thick mode)
        # Commented out as we're using thin mode by default
        # oracledb.init_oracle_client()

        # Create connection using the thin mode (default)
        connection = oracledb.connect(
            user=ORACLE_USER,
            password=ORACLE_SYNC_PASSWORD,
            dsn=f"{ORACLE_HOST}:{ORACLE_PORT}/{ORACLE_SERVICE}"
        )
        logger.info("Connected to Oracle database successfully")
        return connection
    except Exception as e:
        logger.error(f"Error connecting to Oracle: {e}")
        raise

def get_clickhouse_connection():
    """Establish connection to ClickHouse database"""
    try:
        client = clickhouse_driver.Client(
            host=CLICKHOUSE_HOST,
            user=CLICKHOUSE_USER,
            password=CLICKHOUSE_PASSWORD,
            database=CLICKHOUSE_DB
        )
        logger.info("Connected to ClickHouse database successfully")
        return client
    except Exception as e:
        logger.error(f"Error connecting to ClickHouse: {e}")
        raise

def get_last_sync_id(clickhouse_client):
    """Get the ID of the last synchronized record"""
    try:
        result = clickhouse_client.execute(
            f"SELECT MAX(act_aa_id) FROM {CLICKHOUSE_DB}.support_tasks"
        )
        last_id = result[0][0] if result[0][0] else ""
        logger.info(f"Last synced ID: {last_id}")
        return last_id
    except Exception as e:
        logger.error(f"Error getting last sync ID: {e}")
        return ""

def sync_data(oracle_conn, clickhouse_client, batch_size=1000):
    """Sync data from Oracle to ClickHouse"""
    last_id = get_last_sync_id(clickhouse_client)

    # Prepare Oracle query for incremental load
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
    WHERE sta.AA_ID > :last_id
    ORDER BY sta.AA_ID
    """

    try:
        cursor = oracle_conn.cursor()
        # Bind parameter for query
        cursor.execute(query, [last_id])  # Using list instead of named parameters

        total_records = 0
        while True:
            rows = cursor.fetchmany(batch_size)
            if not rows:
                break

            # Convert Oracle data to DataFrame
            columns = [col[0].lower() for col in cursor.description]
            df = pd.DataFrame(rows, columns=columns)

            # Handle NaT and convert dates
            for col in df.columns:
                if df[col].dtype == 'object':
                    try:
                        # Convert Oracle DATE to Python datetime
                        if col in ['createddatetime', 'actdatetime']:
                            df[col] = pd.to_datetime(df[col])
                    except:
                        pass

            # Insert data into ClickHouse
            data_list = df.to_dict('records')
            if data_list:
                columns = list(df.columns)
                clickhouse_client.execute(
                    f"INSERT INTO {CLICKHOUSE_DB}.support_tasks ({', '.join(columns)}) VALUES",
                    data_list
                )

                total_records += len(data_list)
                logger.info(f"Inserted {len(data_list)} records, total: {total_records}")

        logger.info(f"Sync completed. Total records: {total_records}")
        return total_records

    except Exception as e:
        logger.error(f"Error during sync: {e}")
        raise
    finally:
        if 'cursor' in locals():
            cursor.close()

def main():
    """Main function to run the synchronization process"""
    logger.info("Starting Oracle to ClickHouse sync process")

    try:
        # Wait for ClickHouse to be ready
        clickhouse_client = None
        retries = 5
        while retries > 0:
            try:
                clickhouse_client = get_clickhouse_connection()
                break
            except Exception:
                retries -= 1
                logger.info(f"Waiting for ClickHouse to be ready... {retries} retries left")
                time.sleep(5)

        if not clickhouse_client:
            logger.error("Failed to connect to ClickHouse after multiple attempts")
            return

        # Connect to Oracle
        oracle_conn = get_oracle_connection()

        # Perform initial sync
        records_synced = sync_data(oracle_conn, clickhouse_client)

        # If running in container, keep syncing at regular intervals
        if os.environ.get('DOCKER_CONTAINER'):
            while True:
                logger.info("Waiting 5 minutes before next sync...")
                time.sleep(300)  # 5 minutes
                sync_data(oracle_conn, clickhouse_client)

    except Exception as e:
        logger.error(f"Sync process failed: {e}")

    finally:
        if 'oracle_conn' in locals() and oracle_conn:
            oracle_conn.close()
            logger.info("Oracle connection closed")

if __name__ == "__main__":
    main()
