#!/usr/bin/env python3
import os
import logging
import time
import sys
import traceback
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional, Callable, Tuple, Union
import pandas as pd
import oracledb
import clickhouse_driver
from dotenv import load_dotenv

#####################################
# LOGGING CONFIGURATION
#####################################

# Configure detailed logging
def setup_logging():
    """Set up enhanced logging with file and console output."""
    log_dir = "logs"
    if not os.path.exists(log_dir):
        os.makedirs(log_dir)

    log_file = os.path.join(log_dir, f"sync_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log")

    # Create a formatter for detailed logs
    detailed_formatter = logging.Formatter(
        '%(asctime)s - %(levelname)s - [%(name)s] %(message)s - (%(filename)s:%(lineno)d)'
    )

    # Simple formatter for console
    console_formatter = logging.Formatter(
        '%(asctime)s - %(levelname)s - %(message)s'
    )

    # File handler for all logs
    file_handler = logging.FileHandler(log_file)
    file_handler.setLevel(logging.DEBUG)
    file_handler.setFormatter(detailed_formatter)

    # Console handler for info+ logs
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    console_handler.setFormatter(console_formatter)

    # Root logger configuration
    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)
    root_logger.addHandler(file_handler)
    root_logger.addHandler(console_handler)

    # Create module loggers
    global logger, oracle_logger, clickhouse_logger, converter_logger, syncer_logger

    logger = logging.getLogger('oracle_sync')
    oracle_logger = logging.getLogger('oracle_connector')
    clickhouse_logger = logging.getLogger('clickhouse_connector')
    converter_logger = logging.getLogger('type_converter')
    syncer_logger = logging.getLogger('data_syncer')

    logger.info("Logging initialized")
    logger.info(f"Detailed logs will be written to: {log_file}")

# Initialize loggers as global variables
logger = logging.getLogger('oracle_sync')
oracle_logger = logging.getLogger('oracle_connector')
clickhouse_logger = logging.getLogger('clickhouse_connector')
converter_logger = logging.getLogger('type_converter')
syncer_logger = logging.getLogger('data_syncer')

#####################################
# DATA TYPE CONVERSION SYSTEM
#####################################

class DataTypeConverter:
    """
    A reusable system for converting data types between different database systems.
    This class handles conversion of data types and provides defaults for missing/null values.
    """

    # Mapping of ClickHouse data types to Python conversion functions
    TYPE_CONVERTERS = {
        'Int8': int,
        'Int16': int,
        'Int32': int,
        'Int64': int,
        'Int128': int,
        'Int256': int,
        'UInt8': int,
        'UInt16': int,
        'UInt32': int,
        'UInt64': int,
        'UInt128': int,
        'UInt256': int,
        'Float32': float,
        'Float64': float,
        'Decimal': float,
        'String': str,
        'FixedString': str,
        'UUID': str,
        'Date': lambda x: pd.to_datetime(x).date() if pd.notna(x) else None,
        'DateTime': lambda x: pd.to_datetime(x) if pd.notna(x) else None,
        'DateTime64': lambda x: pd.to_datetime(x) if pd.notna(x) else None,
        'Enum8': str,
        'Enum16': str,
        'Bool': bool
    }

    # Default values for ClickHouse data types when source value is None/NULL
    DEFAULT_VALUES = {
        'Int8': 0,
        'Int16': 0,
        'Int32': 0,
        'Int64': 0,
        'Int128': 0,
        'Int256': 0,
        'UInt8': 0,
        'UInt16': 0,
        'UInt32': 0,
        'UInt64': 0,
        'UInt128': 0,
        'UInt256': 0,
        'Float32': 0.0,
        'Float64': 0.0,
        'Decimal': 0.0,
        'String': '',
        'FixedString': '',
        'UUID': '00000000-0000-0000-0000-000000000000',
        'Date': None,
        'DateTime': None,
        'DateTime64': None,
        'Enum8': '',
        'Enum16': '',
        'Bool': False
    }

    def __init__(self, schema_mapping: Dict[str, str]) -> None:
        """
        Initialize the converter with a mapping of column names to target data types.

        Args:
            schema_mapping: Dictionary mapping column names to their target data types
                           e.g., {'user_id': 'UInt32', 'name': 'String', 'created_at': 'DateTime'}
        """
        self.schema_mapping = schema_mapping
        converter_logger.debug(f"DataTypeConverter initialized with schema: {schema_mapping}")

    def convert_record(self, record: Dict[str, Any]) -> Dict[str, Any]:
        """
        Convert a single record's data types according to the schema mapping.

        Args:
            record: Dictionary containing a single record's data

        Returns:
            Converted record with appropriate data types
        """
        converted_record = {}

        for column, value in record.items():
            # Only convert columns specified in the schema mapping
            if column in self.schema_mapping:
                target_type = self.schema_mapping[column]
                original_value = value
                converted_value = self._convert_value(value, target_type)

                # Log conversions for debugging, especially when values change significantly
                if str(original_value) != str(converted_value):
                    converter_logger.debug(f"Converted {column}: {original_value} ({type(original_value)}) -> {converted_value} ({type(converted_value)}) as {target_type}")

                converted_record[column] = converted_value
            else:
                # Pass through any columns not specified in schema mapping
                converted_record[column] = value
                converter_logger.debug(f"Passing through unmapped column {column} with value {value}")

        return converted_record

    def convert_records(self, records: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """
        Convert multiple records according to the schema mapping.

        Args:
            records: List of record dictionaries

        Returns:
            List of converted records
        """
        if not records:
            converter_logger.warning("No records to convert")
            return []

        start_time = time.time()
        converted = [self.convert_record(record) for record in records]
        elapsed = time.time() - start_time

        converter_logger.info(f"Converted {len(records)} records in {elapsed:.2f}s")

        # Log a sample record before and after conversion for verification
        if records:
            sample_idx = min(5, len(records) - 1)  # Get the 5th record or the last one if fewer than 5 records
            converter_logger.debug(f"Sample record before conversion: {records[sample_idx]}")
            converter_logger.debug(f"Sample record after conversion: {converted[sample_idx]}")

        return converted

    def _convert_value(self, value: Any, target_type: str) -> Any:
        """
        Convert a single value to the target data type.

        Args:
            value: The value to convert
            target_type: The target ClickHouse data type

        Returns:
            Converted value
        """
        # Handle None/NULL values
        if value is None:
            default_value = self.DEFAULT_VALUES.get(target_type, None)
            converter_logger.debug(f"Converting NULL value to default {default_value} for type {target_type}")
            return default_value

        # Get the appropriate converter for this type
        converter = self.TYPE_CONVERTERS.get(target_type)

        if converter is None:
            # If no converter defined for this type, return as-is
            converter_logger.warning(f"No converter defined for type: {target_type}")
            return value

        try:
            return converter(value)
        except (ValueError, TypeError) as e:
            # Log the error and return the default value
            converter_logger.warning(f"Error converting value '{value}' ({type(value)}) to {target_type}: {e}")
            default_value = self.DEFAULT_VALUES.get(target_type, None)
            converter_logger.debug(f"Using default value {default_value} for type {target_type}")
            return default_value

#####################################
# DATABASE CONNECTORS
#####################################

class OracleConnector:
    """Database connector for Oracle."""

    def __init__(self, user: str, password: str, host: str, port: str, service: str) -> None:
        self.user = user
        self.password = password
        self.host = host
        self.port = port
        self.service = service
        self.connection = None

        oracle_logger.debug(f"OracleConnector initialized with host={host}, port={port}, service={service}, user={user}")

    def connect(self) -> oracledb.Connection:
        """Establish connection to Oracle database."""
        try:
            oracle_logger.info(f"Connecting to Oracle database at {self.host}:{self.port}/{self.service}")
            start_time = time.time()

            self.connection = oracledb.connect(
                user=self.user,
                password=self.password,
                dsn=f"{self.host}:{self.port}/{self.service}"
            )

            elapsed = time.time() - start_time
            oracle_logger.info(f"Connected to Oracle database in {elapsed:.2f}s")

            # Test the connection with a simple query
            cursor = self.connection.cursor()
            try:
                cursor.execute("SELECT 1 FROM DUAL")
                result = cursor.fetchone()
                oracle_logger.debug(f"Connection test query result: {result}")
            finally:
                cursor.close()

            return self.connection
        except Exception as e:
            oracle_logger.error(f"Error connecting to Oracle: {e}")
            oracle_logger.error(f"Connection details: {self.host}:{self.port}/{self.service}")
            oracle_logger.debug(traceback.format_exc())
            raise

    def execute_query(self, query: str, params: Optional[List[Any]] = None,
                      batch_size: int = 1000) -> Tuple[List[str], List[Tuple]]:
        """
        Execute a query and return column names and rows.

        Args:
            query: SQL query to execute
            params: Query parameters
            batch_size: Number of rows to fetch at once

        Returns:
            Tuple of (column_names, rows)
        """
        if self.connection is None:
            self.connect()

        oracle_logger.info(f"Executing Oracle query with params: {params}")
        oracle_logger.debug(f"Oracle query: {query}")

        cursor = self.connection.cursor()
        try:
            start_time = time.time()
            cursor.execute(query, params or [])
            execute_time = time.time() - start_time
            oracle_logger.debug(f"Query executed in {execute_time:.2f}s")

            columns = [col[0].lower() for col in cursor.description]
            oracle_logger.debug(f"Query returned columns: {columns}")

            # Fetch rows in batches
            all_rows = []
            while True:
                batch_start = time.time()
                rows = cursor.fetchmany(batch_size)
                batch_time = time.time() - batch_start

                if not rows:
                    break

                all_rows.extend(rows)
                oracle_logger.debug(f"Fetched {len(rows)} rows in {batch_time:.2f}s, total rows so far: {len(all_rows)}")

                # If fetched less than batch size, no need to query again
                if len(rows) < batch_size:
                    break

            oracle_logger.info(f"Oracle query completed: {len(all_rows)} rows returned in {time.time() - start_time:.2f}s")
            return columns, all_rows
        except Exception as e:
            oracle_logger.error(f"Oracle query error: {e}")
            oracle_logger.error(f"Failed query: {query}")
            oracle_logger.debug(traceback.format_exc())
            raise
        finally:
            cursor.close()

    def close(self) -> None:
        """Close the database connection."""
        if self.connection:
            oracle_logger.info("Closing Oracle connection")
            self.connection.close()
            self.connection = None

class ClickHouseConnector:
    """Database connector for ClickHouse."""

    def __init__(self, host: str, user: str, password: str, database: str) -> None:
        self.host = host
        self.user = user
        self.password = password
        self.database = database
        self.client = None

        clickhouse_logger.debug(f"ClickHouseConnector initialized with host={host}, database={database}, user={user}")

    def connect(self) -> clickhouse_driver.Client:
        """Establish connection to ClickHouse database."""
        try:
            # Add settings to improve protocol compatibility
            clickhouse_logger.info(f"Connecting to ClickHouse database at {self.host}, db={self.database}")
            start_time = time.time()

            self.client = clickhouse_driver.Client(
                host=self.host,
                user=self.user,
                password=self.password,
                database=self.database,
                settings={
                    'use_numpy': False,  # Avoid numpy integration issues
                    'max_block_size': 100000,  # Reasonable block size
                    'send_progress_in_http_headers': 0,  # Simplify communication
                    'connect_timeout': 10,  # More generous timeouts
                    'receive_timeout': 300,
                    'send_timeout': 300
                }
            )

            elapsed = time.time() - start_time
            clickhouse_logger.info(f"Connected to ClickHouse database in {elapsed:.2f}s")

            # Test connection with simple query
            try:
                test_result = self.client.execute("SELECT 1")
                clickhouse_logger.debug(f"Connection test query result: {test_result}")
            except Exception as test_error:
                clickhouse_logger.warning(f"Connection test query failed: {test_error}")

            return self.client
        except Exception as e:
            clickhouse_logger.error(f"Error connecting to ClickHouse: {e}")
            clickhouse_logger.error(f"Connection details: host={self.host}, db={self.database}, user={self.user}")
            clickhouse_logger.debug(traceback.format_exc())
            raise

    def execute(self, query: str, params: Optional[List[Any]] = None) -> List[Tuple]:
        """Execute a query and return results."""
        if self.client is None:
            self.connect()

        clickhouse_logger.debug(f"Executing ClickHouse query: {query}")
        if params:
            clickhouse_logger.debug(f"Query parameters: {params}")

        try:
            start_time = time.time()
            result = self.client.execute(query, params or [])
            elapsed = time.time() - start_time

            clickhouse_logger.debug(f"Query executed in {elapsed:.2f}s, returned {len(result)} rows")
            if result and len(result) > 0:
                clickhouse_logger.debug(f"First row of result: {result[0]}")

            return result
        except Exception as e:
            clickhouse_logger.error(f"Query execution error: {e}")
            clickhouse_logger.error(f"Failed query: {query}")
            clickhouse_logger.debug(traceback.format_exc())
            raise

    def insert_data(self, table: str, columns: List[str], data: List[Dict[str, Any]]) -> int:
        """
        Insert data into ClickHouse table.

        Args:
            table: Table name
            columns: List of column names
            data: List of record dictionaries

        Returns:
            Number of inserted records
        """
        if self.client is None:
            self.connect()

        clickhouse_logger.info(f"Inserting {len(data)} records into {self.database}.{table}")
        clickhouse_logger.debug(f"Table columns: {columns}")

        # Log sample data for troubleshooting
        if data:
            sample_record = data[0]
            clickhouse_logger.debug(f"Sample record: {sample_record}")

            # Log the types of each field in the sample record
            type_info = {k: f"{type(v).__name__}" for k, v in sample_record.items()}
            clickhouse_logger.debug(f"Data types in sample record: {type_info}")

        try:
            start_time = time.time()

            # Split data into smaller batches to avoid large packets
            batch_size = 10000
            total_inserted = 0

            for i in range(0, len(data), batch_size):
                batch = data[i:i+batch_size]
                batch_start = time.time()

                self.client.execute(
                    f"INSERT INTO {self.database}.{table} ({', '.join(columns)}) VALUES",
                    batch
                )

                batch_time = time.time() - batch_start
                total_inserted += len(batch)
                clickhouse_logger.info(f"Inserted batch of {len(batch)} records in {batch_time:.2f}s, total: {total_inserted}")

            elapsed = time.time() - start_time
            clickhouse_logger.info(f"Total insertion completed in {elapsed:.2f}s, {total_inserted} records inserted")

            return total_inserted
        except Exception as e:
            clickhouse_logger.error(f"Error inserting data: {e}")

            if data:
                # Log more details about the data that failed
                clickhouse_logger.error(f"First record: {data[0]}")

                # Check if there are NULL values in key fields
                null_fields = []
                for record in data[:5]:  # Check first 5 records
                    for key, value in record.items():
                        if value is None:
                            null_fields.append(key)

                if null_fields:
                    clickhouse_logger.error(f"Found NULL values in fields: {set(null_fields)}")

                # Try to identify problematic records
                for i, record in enumerate(data[:20]):  # Check first 20 records
                    try:
                        # Test serialization
                        for k, v in record.items():
                            if isinstance(v, (int, float, str, datetime, bool)) or v is None:
                                continue
                            clickhouse_logger.error(f"Record {i}, field {k} has non-standard type: {type(v)}")
                    except Exception as record_error:
                        clickhouse_logger.error(f"Problem with record {i}: {record_error}")

            clickhouse_logger.debug(traceback.format_exc())
            raise

    def get_last_sync_id(self, table: str, id_column: str) -> Union[str, int]:
        """Get the ID of the last synchronized record."""
        try:
            clickhouse_logger.info(f"Getting last sync ID from {table} using column {id_column}")

            # First check if the table exists
            try:
                exists_query = f"EXISTS TABLE {self.database}.{table}"
                clickhouse_logger.debug(f"Checking if table exists: {exists_query}")

                exists_result = self.execute(exists_query)
                table_exists = exists_result[0][0] if exists_result and exists_result[0] else False

                if not table_exists:
                    clickhouse_logger.warning(f"Table {self.database}.{table} does not exist")
                    return 0

                clickhouse_logger.debug(f"Table {self.database}.{table} exists")
            except Exception as exists_error:
                clickhouse_logger.warning(f"Error checking if table exists: {exists_error}")

            # Use a more explicit query format with explicit type conversion
            query = f"""
                SELECT COALESCE(MAX({id_column}), '0')
                FROM {self.database}.{table}
            """
            clickhouse_logger.debug(f"Executing query: {query}")

            # First try with direct execution
            try:
                result = self.execute(query)
                last_id = result[0][0] if result and result[0] else 0
                clickhouse_logger.info(f"Last synced ID: {last_id}")
                return last_id
            except Exception as first_error:
                # If fails, try alternative approach with more basic query
                clickhouse_logger.warning(f"First attempt failed: {first_error}, trying alternative approach")

                try:
                    # Try with a simpler count query first to verify basic functionality
                    count_query = f"SELECT COUNT(*) FROM {self.database}.{table}"
                    clickhouse_logger.debug(f"Trying count query: {count_query}")

                    test_result = self.execute(count_query)
                    count = test_result[0][0] if test_result else 0
                    clickhouse_logger.info(f"Table has {count} rows")

                    # If count is 0, we know there's no last ID
                    if count == 0:
                        return 0

                    # Try with a different query approach (limit 1)
                    alt_query = f"""
                        SELECT {id_column}
                        FROM {self.database}.{table}
                        ORDER BY {id_column} DESC
                        LIMIT 1
                    """
                    clickhouse_logger.debug(f"Trying alternative query: {alt_query}")

                    alt_result = self.execute(alt_query)
                    last_id = alt_result[0][0] if alt_result and alt_result[0] else 0
                    clickhouse_logger.info(f"Last synced ID (alternative method): {last_id}")
                    return last_id

                except Exception as second_error:
                    # If all queries fail, something more fundamental is wrong
                    clickhouse_logger.error(f"Alternative approach also failed: {second_error}")
                    clickhouse_logger.debug(traceback.format_exc())

                    # Return 0 as a safe default
                    return 0

        except Exception as e:
            clickhouse_logger.error(f"Error getting last sync ID: {e}")
            clickhouse_logger.debug(traceback.format_exc())
            return 0

#####################################
# ETL ORCHESTRATION
#####################################

class OracleToClickHouseSyncer:
    """
    Synchronizes data from Oracle to ClickHouse with proper type conversion.
    This class orchestrates the entire ETL process.
    """

    def __init__(
        self,
        oracle_connector: OracleConnector,
        clickhouse_connector: ClickHouseConnector,
        type_converter: DataTypeConverter,
        source_query: str,
        target_table: str,
        id_column: str = 'act_aa_id',
        batch_size: int = 1000
    ) -> None:
        self.oracle = oracle_connector
        self.clickhouse = clickhouse_connector
        self.converter = type_converter
        self.source_query = source_query
        self.target_table = target_table
        self.id_column = id_column
        self.batch_size = batch_size

        syncer_logger.debug(f"Syncer initialized for target table: {target_table}, using ID column: {id_column}")

    def sync(self) -> int:
        """
        Perform the synchronization process.

        Returns:
            Number of synchronized records
        """
        syncer_logger.info(f"Starting synchronization to table {self.target_table}")
        sync_start = time.time()

        try:
            # Connect to both databases
            syncer_logger.info("Establishing database connections")
            self.oracle.connect()
            self.clickhouse.connect()

            # Get last synced ID
            syncer_logger.info(f"Getting last synced ID from {self.target_table}")
            last_id = self.clickhouse.get_last_sync_id(self.target_table, self.id_column)
            syncer_logger.info(f"Last synced ID: {last_id}")

            # Execute query with parameter binding
            syncer_logger.info(f"Executing Oracle query with last_id = {last_id}")
            columns, rows = self.oracle.execute_query(
                self.source_query,
                [last_id],
                batch_size=self.batch_size
            )

            # Convert to DataFrame
            syncer_logger.info(f"Converting {len(rows)} rows to DataFrame")
            df_start = time.time()
            df = pd.DataFrame(rows, columns=columns)
            df_time = time.time() - df_start
            syncer_logger.info(f"DataFrame conversion completed in {df_time:.2f}s")

            if df.empty:
                syncer_logger.info("No new data to sync")
                return 0

            # Log DataFrame info for debugging
            syncer_logger.debug(f"DataFrame columns: {df.columns.tolist()}")
            syncer_logger.debug(f"DataFrame shape: {df.shape}")

            # Check for any missing or problematic columns
            expected_columns = list(self.converter.schema_mapping.keys())
            missing_columns = [col for col in expected_columns if col not in df.columns]
            if missing_columns:
                syncer_logger.warning(f"Missing expected columns in query results: {missing_columns}")

            # Log datatypes of DataFrame columns
            dtypes_dict = {col: str(df[col].dtype) for col in df.columns}
            syncer_logger.debug(f"DataFrame column types: {dtypes_dict}")

            # Convert to list of dictionaries
            syncer_logger.info("Converting DataFrame to dictionary records")
            dict_start = time.time()
            data_list = df.to_dict('records')
            dict_time = time.time() - dict_start
            syncer_logger.info(f"Dictionary conversion completed in {dict_time:.2f}s")

            # Convert data types
            syncer_logger.info("Converting data types for ClickHouse")
            conv_start = time.time()
            converted_data = self.converter.convert_records(data_list)
            conv_time = time.time() - conv_start
            syncer_logger.info(f"Data type conversion completed in {conv_time:.2f}s")

            # Insert into ClickHouse
            syncer_logger.info(f"Inserting {len(converted_data)} records into ClickHouse")
            insert_start = time.time()
            inserted = self.clickhouse.insert_data(
                self.target_table,
                columns,
                converted_data
            )
            insert_time = time.time() - insert_start
            syncer_logger.info(f"Data insertion completed in {insert_time:.2f}s")

            total_time = time.time() - sync_start
            syncer_logger.info(f"Sync completed. {inserted} records synchronized in {total_time:.2f}s")
            return inserted

        except Exception as e:
            syncer_logger.error(f"Sync process failed: {e}")
            syncer_logger.debug(traceback.format_exc())
            raise
        finally:
            self.oracle.close()

#####################################
# MAIN APPLICATION
#####################################

def get_schema_mapping() -> Dict[str, str]:
    """
    Define the schema mapping for the support_tasks table.
    This maps column names to their ClickHouse data types.
    """
    return {
        'act_aa_id': 'String',
        'task_id': 'String',
        'client': 'String',
        'status12': 'String',
        'createddatetime': 'DateTime',
        'group': 'String',
        'company': 'String',
        'position': 'String',
        'job_classification': 'String',
        'email': 'String',
        'dept_descr': 'String',
        'div_descr': 'String',
        'liveissue': 'String',
        'task_class': 'String',
        'pr_ac_sort': 'Int32',  # Changed to Int32 to support negative values
        'viewyn': 'String',
        'actdatetime': 'DateTime',
        'actioncode12': 'String',
        'actempl': 'String',
        'assignedto': 'String',
        'task_aa_id': 'String',
        'product': 'String'
    }

def get_source_query() -> str:
    """
    Define the query to fetch data from Oracle.
    """
    return """
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

def main() -> None:
    """Main function to run the synchronization process."""
    try:
        # Initialize enhanced logging
        setup_logging()

        logger.info("=" * 80)
        logger.info(f"ORACLE TO CLICKHOUSE SYNC STARTING - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        logger.info("=" * 80)

        # Load environment variables
        logger.info("Loading environment variables")
        load_dotenv()

        # Database configuration from environment variables
        ORACLE_USER = os.getenv('ORACLE_USER')
        ORACLE_SYNC_PASSWORD = os.getenv('ORACLE_SYNC_PASSWORD')
        ORACLE_HOST = os.getenv('ORACLE_HOST')
        ORACLE_PORT = os.getenv('ORACLE_PORT', '1521')
        ORACLE_SERVICE = os.getenv('ORACLE_SERVICE')

        CLICKHOUSE_HOST = os.getenv('CLICKHOUSE_HOST', 'clickhouse')
        CLICKHOUSE_USER = os.getenv('CLICKHOUSE_USER', 'default')
        CLICKHOUSE_PASSWORD = os.getenv('CLICKHOUSE_PASSWORD', 'default')
        CLICKHOUSE_DB = os.getenv('CLICKHOUSE_DB', 'support_analytics')

        # Log configuration (hiding passwords)
        logger.info(f"Oracle configuration: USER={ORACLE_USER}, HOST={ORACLE_HOST}, PORT={ORACLE_PORT}, SERVICE={ORACLE_SERVICE}")
        logger.info(f"ClickHouse configuration: HOST={CLICKHOUSE_HOST}, DB={CLICKHOUSE_DB}, USER={CLICKHOUSE_USER}")

        # Set Oracle environment variables
        os.environ['NLS_LANG'] = 'AMERICAN_AMERICA.AL32UTF8'
        logger.info("Set Oracle NLS_LANG environment variable")

        # Also set Docker container environment flag
        if os.environ.get('DOCKER_CONTAINER') is None:
            logger.info("Setting DOCKER_CONTAINER environment variable to 1")
            os.environ['DOCKER_CONTAINER'] = "1"

        try:
            # Create database connectors
            logger.info("Initializing database connectors")
            oracle_connector = OracleConnector(
                user=ORACLE_USER,
                password=ORACLE_SYNC_PASSWORD,
                host=ORACLE_HOST,
                port=ORACLE_PORT,
                service=ORACLE_SERVICE
            )

            clickhouse_connector = ClickHouseConnector(
                host=CLICKHOUSE_HOST,
                user=CLICKHOUSE_USER,
                password=CLICKHOUSE_PASSWORD,
                database=CLICKHOUSE_DB
            )

            # Wait for ClickHouse to be ready
            logger.info("Waiting for ClickHouse to be ready")
            retries = 5
            while retries > 0:
                try:
                    clickhouse_connector.connect()
                    break
                except Exception as e:
                    retries -= 1
                    logger.warning(f"ClickHouse connection attempt failed: {e}")
                    logger.info(f"Waiting for ClickHouse to be ready... {retries} retries left")
                    time.sleep(5)

            if retries <= 0:
                logger.error("Failed to connect to ClickHouse after multiple attempts")
                return

            # Create type converter
            logger.info("Initializing data type converter")
            type_converter = DataTypeConverter(get_schema_mapping())

            # Create syncer
            logger.info("Initializing data syncer")
            syncer = OracleToClickHouseSyncer(
                oracle_connector=oracle_connector,
                clickhouse_connector=clickhouse_connector,
                type_converter=type_converter,
                source_query=get_source_query(),
                target_table='support_tasks'
            )

            # Perform initial sync
            logger.info("Starting initial data synchronization")
            syncer.sync()

            # If running in container, keep syncing at regular intervals
            if os.environ.get('DOCKER_CONTAINER'):
                logger.info("Running in container mode, will continue with periodic syncs")
                sync_interval = int(os.getenv('SYNC_INTERVAL_SECONDS', '3600'))  # Default to 1 hour

                while True:
                    logger.info(f"Waiting {sync_interval} seconds before next sync...")
                    time.sleep(sync_interval)
                    logger.info("Starting periodic data synchronization")
                    syncer.sync()
            else:
                logger.info("Not running in container mode, exiting after initial sync")

        except Exception as e:
            logger.error(f"Application failed: {e}")
            logger.debug(traceback.format_exc())
            sys.exit(1)

    except Exception as setup_error:
        # Basic logging if setup_logging fails
        print(f"CRITICAL ERROR: Failed to initialize: {setup_error}")
        traceback.print_exc()
        sys.exit(1)

    logger.info("=" * 80)
    logger.info(f"ORACLE TO CLICKHOUSE SYNC COMPLETED - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    logger.info("=" * 80)

if __name__ == "__main__":
    main()
