import pandas as pd 
import mysql.connector


DB_CONFIG = {

"host": "localhost",
"user": "root",
"password": "",
"database": "capstone_db"

}

def get_connection():
    return mysql.connector.connect(**DB_CONFIG)

