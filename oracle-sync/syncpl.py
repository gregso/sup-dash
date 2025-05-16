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
    """Synchronize data from Oracle to ClickHouse using polars with explicit schema definition"""

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

        # Define explicit schema mapping for all columns
        # This prevents schema inference issues with mixed data types
        schema_mapping = {
            'act_aa_id': pl.Utf8,           # String columns
            'task_id': pl.Utf8,
            'client': pl.Utf8,
            'status12': pl.Utf8,
            'group': pl.Utf8,
            'company': pl.Utf8,
            'position': pl.Utf8,
            'job_classification': pl.Utf8,
            'email': pl.Utf8,
            'dept_descr': pl.Utf8,
            'div_descr': pl.Utf8,
            'liveissue': pl.Utf8,
            'task_class': pl.Utf8,
            'viewyn': pl.Utf8,
            'actioncode12': pl.Utf8,
            'actempl': pl.Utf8,
            'assignedto': pl.Utf8,
            'task_aa_id': pl.Utf8,
            'product': pl.Utf8,
            'pr_ac_sort': pl.Int32,         # Integer column
            'createddatetime': pl.Datetime, # DateTime columns
            'actdatetime': pl.Datetime
        }

        # Connect to Oracle
        logger.info(f"Connecting to Oracle at {oracle_host}:{oracle_port}/{oracle_service}")
        dsn = f"{oracle_host}:{oracle_port}/{oracle_service}"

        with oracledb.connect(user=oracle_user, password=oracle_password, dsn=dsn) as oracle_conn:
            cursor = oracle_conn.cursor()


            no_of_days = 3*365
            # Query for data newer than the last synced ID
            query = f"""
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
            WHERE sta.AA_ID > :last_id AND sta.ACTDATETIME >= TRUNC(SYSDATE - {no_of_days})
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

                logger.info(f"Processing batch of {len(rows)} records with polars")

                # Two-step process to handle data type conversion safely with polars

                # Step 1: Create a polars DataFrame from rows with row orientation
                # We won't use schema here initially to avoid conversion errors
                raw_df = pl.DataFrame(rows, schema=None, orient="row")
                raw_df.columns = columns

                # Step 2: Convert each column to the appropriate type using expressions
                # This allows more flexible handling of type conversion errors
                expressions = []

                # Add expressions for each column with appropriate type conversion
                for col in raw_df.columns:
                    if col in schema_mapping:
                        target_type = schema_mapping[col]

                        if target_type == pl.Int32:
                            # For integers, handle nulls and conversion errors
                            expressions.append(
                                pl.col(col).fill_null(0).cast(pl.Int32, strict=False)
                            )
                        elif target_type == pl.Datetime:
                            # For datetimes, use specialized conversion
                            expressions.append(
                                pl.col(col).cast(pl.Datetime, strict=False)
                            )
                        elif target_type == pl.Utf8:
                            # For strings, ensure all values are strings and handle nulls
                            expressions.append(
                                pl.col(col).cast(pl.Utf8, strict=False).fill_null("")
                            )
                        else:
                            # Default handling for other types
                            expressions.append(
                                pl.col(col).cast(target_type, strict=False)
                            )
                    else:
                        # If column not in schema, pass through as is
                        expressions.append(pl.col(col))

                # Create new DataFrame with proper types
                df = raw_df.select(expressions)

                # Convert to dictionary records for insertion
                records = df.to_dicts()

                # Insert into ClickHouse
                try:
                    logger.info(f"Inserting {len(records)} records into ClickHouse")
                    clickhouse.execute(
                        f"INSERT INTO {clickhouse_db}.support_tasks ({', '.join(columns)}) VALUES",
                        records
                    )
                    total_records += len(records)
                    logger.info(f"Successfully inserted batch, total: {total_records}")
                except Exception as e:
                    logger.error(f"Error inserting batch into ClickHouse: {e}")
                    if records:
                        logger.error(f"Sample record: {records[0]}")
                        logger.error(f"Types: {[(k, type(v)) for k, v in records[0].items()]}")
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
