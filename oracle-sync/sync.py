#!/usr/bin/env python3
import os
import logging
import time
from datetime import datetime
import pandas as pd
import oracledb
import clickhouse_driver
from dotenv import load_dotenv

# Basic logging setup
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger("sync")

# Load environment variables
load_dotenv()

def sync_oracle_to_clickhouse():
    """Simplified synchronization function with minimal abstractions"""

    # Configuration
    oracle_config = {
        "user": os.getenv('ORACLE_USER'),
        "password": os.getenv('ORACLE_SYNC_PASSWORD'),
        "dsn": f"{os.getenv('ORACLE_HOST')}:{os.getenv('ORACLE_PORT', '1521')}/{os.getenv('ORACLE_SERVICE')}"
    }

    clickhouse_config = {
        "host": os.getenv('CLICKHOUSE_HOST', 'clickhouse'),
        "user": os.getenv('CLICKHOUSE_USER', 'default'),
        "password": os.getenv('CLICKHOUSE_PASSWORD', 'default'),
        "database": os.getenv('CLICKHOUSE_DB', 'support_analytics')
    }

    try:
        # Connect to ClickHouse
        ch_client = clickhouse_driver.Client(**clickhouse_config)

        # Get last synced ID
        try:
            result = ch_client.execute(
                f"SELECT MAX(act_aa_id) FROM {clickhouse_config['database']}.support_tasks"
            )
            last_id = result[0][0] if result[0][0] else 0
        except Exception:
            # Fallback to 0 if query fails
            last_id = 0

        logger.info(f"Last synced ID: {last_id}")

        # Connect to Oracle and get new data
        with oracledb.connect(**oracle_config) as oracle_conn:
            cursor = oracle_conn.cursor()

            # Source query with incremental load
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
            WHERE sta.AA_ID > :last_id AND sta.ACTDATETIME >= TRUNC(SYSDATE - 120)
            ORDER BY sta.AA_ID
            """

            cursor.execute(query, [last_id])
            columns = [col[0].lower() for col in cursor.description]

            # Process in batches
            batch_size = 1000
            total_inserted = 0

            while True:
                rows = cursor.fetchmany(batch_size)
                if not rows:
                    break

                # Convert to DataFrame for easier handling
                df = pd.DataFrame(rows, columns=columns)

                # Directly handle the problematic int field that needs Int32 type
                if 'pr_ac_sort' in df.columns:
                    df['pr_ac_sort'] = df['pr_ac_sort'].astype('Int32').fillna(0)

                # Convert to dict for insertion
                records = df.to_dict('records')

                # Insert into ClickHouse
                ch_client.execute(
                    f"INSERT INTO {clickhouse_config['database']}.support_tasks ({', '.join(columns)}) VALUES",
                    records
                )

                total_inserted += len(records)
                logger.info(f"Inserted {len(records)} records, total: {total_inserted}")

        logger.info(f"Sync completed. Total records: {total_inserted}")
        return total_inserted

    except Exception as e:
        logger.error(f"Sync failed: {e}")
        raise

if __name__ == "__main__":
    while True:
        sync_oracle_to_clickhouse()
        time.sleep(3600)  # 1 hour interval
