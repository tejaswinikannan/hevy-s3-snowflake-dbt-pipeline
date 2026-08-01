-- Run as ACCOUNTADMIN in Snowsight.
-- Creates the database and the three medallion schemas.

CREATE DATABASE IF NOT EXISTS hevy;

USE DATABASE hevy;

CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS gold;

-- Sanity check
SHOW SCHEMAS IN DATABASE hevy;
