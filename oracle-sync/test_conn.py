#!/usr/bin/env python3
import os
import sys
import logging
import time
from datetime import datetime
import oracledb
import clickhouse_driver
from dotenv import load_dotenv

# Configure detailed logging for troubleshooting
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(levelname)s - [%(name)s] %(message)s',
    handlers=[
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger('connection_test')

# Load environment variables
load_dotenv()

# Get database configurations
ORACLE_USER = os.getenv('ORACLE_USER')
ORACLE_SYNC_PASSWORD = os.getenv('ORACLE_SYNC_PASSWORD')
ORACLE_HOST = os.getenv('ORACLE_HOST')
ORACLE_PORT = os.getenv('ORACLE_PORT', '1521')
ORACLE_SERVICE = os.getenv('ORACLE_SERVICE')
ORACLE_SCHEMA = os.getenv('ORACLE_SCHEMA', '')

CLICKHOUSE_HOST = os.getenv('CLICKHOUSE_HOST', 'clickhouse')
CLICKHOUSE_USER = os.getenv('CLICKHOUSE_USER', 'default')
CLICKHOUSE_PASSWORD = os.getenv('CLICKHOUSE_PASSWORD', '')
CLICKHOUSE_DB = os.getenv('CLICKHOUSE_DB', 'support_analytics')

def test_oracle_connection():
    """Test connection to Oracle database with detailed logging"""
    logger.info("🔍 Testing Oracle connection...")
    logger.debug(f"Oracle connection parameters: USER={ORACLE_USER},PASS={ORACLE_SYNC_PASSWORD}, HOST={ORACLE_HOST}, PORT={ORACLE_PORT}, SERVICE={ORACLE_SERVICE}")

    try:
        # Attempt to establish connection
        start_time = time.time()
        connection = oracledb.connect(
            user=ORACLE_USER,
            password=ORACLE_SYNC_PASSWORD,
            dsn=f"{ORACLE_HOST}:{ORACLE_PORT}/{ORACLE_SERVICE}"
        )
        elapsed = time.time() - start_time
        logger.info(f"✅ Successfully connected to Oracle in {elapsed:.2f}s")

        # Test basic query
        cursor = connection.cursor()
        logger.info("🔍 Testing simple Oracle query...")

        try:
            # Get database version
            cursor.execute("SELECT BANNER FROM V$VERSION WHERE ROWNUM = 1")
            version = cursor.fetchone()
            logger.info(f"✅ Oracle version: {version[0] if version else 'Unknown'}")

            # Test a simple query to check schema access
            if ORACLE_SCHEMA:
                cursor.execute(f"SELECT table_name FROM all_tables WHERE owner = '{ORACLE_SCHEMA}' AND ROWNUM <= 5")
            else:
                cursor.execute("SELECT table_name FROM user_tables WHERE ROWNUM <= 5")

            tables = cursor.fetchall()
            if tables:
                logger.info(f"✅ Found tables: {[t[0] for t in tables]}")
            else:
                logger.warning("⚠️ Query executed but no tables found")

            # Test access to the specific tables used in the sync process
            logger.info("🔍 Testing sync tables access...")

            # Testing SDRR_TMS_ACTIONS table
            try:
                cursor.execute("SELECT COUNT(*) FROM SDRR_TMS_ACTIONS WHERE ROWNUM <= 1")
                count = cursor.fetchone()
                logger.info(f"✅ SDRR_TMS_ACTIONS table is accessible")
            except Exception as e:
                logger.error(f"❌ SDRR_TMS_ACTIONS table access failed: {e}")

            # Testing SDRR_TMS_TASKS table
            try:
                cursor.execute("SELECT COUNT(*) FROM SDRR_TMS_TASKS WHERE ROWNUM <= 1")
                count = cursor.fetchone()
                logger.info(f"✅ SDRR_TMS_TASKS table is accessible")
            except Exception as e:
                logger.error(f"❌ SDRR_TMS_TASKS table access failed: {e}")

            # Testing SDRR_TMS_EMPLOYEE_INFO_VIEW view
            try:
                cursor.execute("SELECT COUNT(*) FROM SDRR_TMS_EMPLOYEE_INFO_VIEW WHERE ROWNUM <= 1")
                count = cursor.fetchone()
                logger.info(f"✅ SDRR_TMS_EMPLOYEE_INFO_VIEW view is accessible")
            except Exception as e:
                logger.error(f"❌ SDRR_TMS_EMPLOYEE_INFO_VIEW view access failed: {e}")

        except Exception as e:
            logger.error(f"❌ Oracle query execution failed: {e}")
        finally:
            cursor.close()

        connection.close()
        return True

    except Exception as e:
        logger.error(f"❌ Oracle connection failed: {e}")
        # Provide more detailed error diagnostics
        if "ORA-12154" in str(e):
            logger.error("🔍 This is a TNS resolution error. Check if ORACLE_SERVICE name is correct")
        elif "ORA-12505" in str(e):
            logger.error("🔍 This is a SID/Service name mismatch. Check if you're using correct service name")
        elif "ORA-01017" in str(e):
            logger.error("🔍 Invalid username/password. Check your credentials")
        elif "ORA-28000" in str(e):
            logger.error("🔍 Account is locked. Contact your DBA to unlock it")
        elif "ORA-12541" in str(e):
            logger.error("🔍 No listener. Ensure Oracle listener is running on specified host and port")
        elif "ORA-12170" in str(e):
            logger.error("🔍 Connection timeout. Check if database is reachable and not blocked by firewalls")
        return False

def test_clickhouse_connection():
    """Test connection to ClickHouse database with detailed logging"""
    logger.info("🔍 Testing ClickHouse connection...")
    logger.debug(f"ClickHouse connection parameters: HOST={CLICKHOUSE_HOST}, USER={CLICKHOUSE_USER}, DB={CLICKHOUSE_DB}")

    try:
        # Attempt to establish connection
        start_time = time.time()
        client = clickhouse_driver.Client(
            host=CLICKHOUSE_HOST,
            user=CLICKHOUSE_USER,
            password=CLICKHOUSE_PASSWORD,
            database=CLICKHOUSE_DB
        )
        elapsed = time.time() - start_time
        logger.info(f"✅ Successfully connected to ClickHouse in {elapsed:.2f}s")

        # Test basic query - get ClickHouse version
        logger.info("🔍 Testing simple ClickHouse query...")
        try:
            result = client.execute("SELECT version()")
            logger.info(f"✅ ClickHouse version: {result[0][0]}")

            # Check databases
            result = client.execute("SHOW DATABASES")
            logger.info(f"✅ Available databases: {[r[0] for r in result]}")

            # Check if our database exists
            if CLICKHOUSE_DB in [r[0] for r in result]:
                # Check tables in our database
                result = client.execute(f"SHOW TABLES FROM {CLICKHOUSE_DB}")
                if result:
                    logger.info(f"✅ Tables in {CLICKHOUSE_DB}: {[r[0] for r in result]}")
                else:
                    logger.warning(f"⚠️ No tables found in {CLICKHOUSE_DB} database")

                # Check if support_tasks table exists
                if any(r[0] == 'support_tasks' for r in result):
                    logger.info("🔍 Testing support_tasks table...")

                    # Check table structure
                    result = client.execute(f"DESCRIBE TABLE {CLICKHOUSE_DB}.support_tasks")
                    columns = [f"{r[0]} ({r[1]})" for r in result]
                    logger.info(f"✅ Table structure has {len(columns)} columns")
                    logger.debug(f"Table columns: {columns}")

                    # Check row count
                    result = client.execute(f"SELECT count() FROM {CLICKHOUSE_DB}.support_tasks")
                    count = result[0][0]
                    logger.info(f"✅ Table has {count} rows")

                    # If table has data, check the most recent record
                    if count > 0:
                        result = client.execute(f"""
                            SELECT act_aa_id, task_id, client, status12,
                                   toVarcharOrNull(createddatetime) as created,
                                   toVarcharOrNull(_sync_time) as synced
                            FROM {CLICKHOUSE_DB}.support_tasks
                            ORDER BY _sync_time DESC LIMIT 1
                        """)
                        if result:
                            logger.info(f"✅ Most recent record: task_id={result[0][1]}, synced={result[0][5]}")
                else:
                    logger.error(f"❌ Table 'support_tasks' not found in {CLICKHOUSE_DB}")
            else:
                logger.error(f"❌ Database {CLICKHOUSE_DB} does not exist")

        except Exception as e:
            logger.error(f"❌ ClickHouse query execution failed: {e}")

        return True

    except Exception as e:
        logger.error(f"❌ ClickHouse connection failed: {e}")
        # Provide more detailed error diagnostics
        if "Connection refused" in str(e):
            logger.error("🔍 Connection refused. Check if ClickHouse server is running and network is properly configured")
        elif "Authentication failed" in str(e):
            logger.error("🔍 Authentication failed. Check your credentials")
        elif "Database does not exist" in str(e):
            logger.error(f"🔍 Database {CLICKHOUSE_DB} does not exist. Check database name or if init script ran correctly")
        return False

def main():
    """Main test function"""
    logger.info("=" * 50)
    logger.info("ORACLE-SYNC CONNECTION TEST TOOL")
    logger.info("=" * 50)
    logger.info(f"Test started at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("-" * 50)

    # Test Oracle connection
    oracle_success = test_oracle_connection()

    logger.info("-" * 50)

    # Test ClickHouse connection
    clickhouse_success = test_clickhouse_connection()

    logger.info("-" * 50)

    # Summary
    logger.info("TEST SUMMARY:")
    logger.info(f"Oracle connection: {'✅ SUCCESS' if oracle_success else '❌ FAILED'}")
    logger.info(f"ClickHouse connection: {'✅ SUCCESS' if clickhouse_success else '❌ FAILED'}")

    if not oracle_success and not clickhouse_success:
        logger.error("Both database connections failed. The sync process cannot work!")
        sys.exit(1)
    elif not oracle_success:
        logger.error("Oracle connection failed. Sync cannot read source data!")
        sys.exit(1)
    elif not clickhouse_success:
        logger.error("ClickHouse connection failed. Sync cannot write destination data!")
        sys.exit(1)
    else:
        logger.info("✅ All connections successful! The oracle-sync container should work properly.")

if __name__ == "__main__":
    main()
