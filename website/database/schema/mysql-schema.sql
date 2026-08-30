/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;
DROP TABLE IF EXISTS `audit_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `audit_log` (
  `AUD_ID` char(6) NOT NULL COMMENT 'Unique audit log identifier',
  `AUD_ACTION` varchar(100) NOT NULL COMMENT 'Action performed by admin',
  `AUD_DETAILS` text DEFAULT NULL COMMENT 'Brief description of the change',
  `AUD_CREATED_AT` datetime NOT NULL COMMENT 'When the action was performed',
  `USR_ID` char(6) NOT NULL COMMENT 'Admin who performed the action',
  PRIMARY KEY (`AUD_ID`),
  KEY `FK_AUDITLOG_USER` (`USR_ID`),
  CONSTRAINT `FK_AUDITLOG_USER` FOREIGN KEY (`USR_ID`) REFERENCES `user` (`USR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Audit trail of administrative actions';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `buyer`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `buyer` (
  `BUY_ID` char(6) NOT NULL COMMENT 'Unique buyer identifier',
  `BUY_CURRENT_LATITUDE` decimal(10,8) DEFAULT NULL COMMENT 'Current GPS latitude of buyer',
  `BUY_CURRENT_LONGITUDE` decimal(11,8) DEFAULT NULL COMMENT 'Current GPS longitude of buyer',
  `BUY_LOC_UPDATED_AT` datetime DEFAULT NULL COMMENT 'Last location updated',
  `USR_ID` char(6) NOT NULL COMMENT 'References the user account',
  PRIMARY KEY (`BUY_ID`),
  UNIQUE KEY `UX_BUYER_USR` (`USR_ID`),
  CONSTRAINT `FK_BUYER_USER` FOREIGN KEY (`USR_ID`) REFERENCES `user` (`USR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Buyer profile extension of USER';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cache`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cache` (
  `key` varchar(255) NOT NULL,
  `value` mediumtext NOT NULL,
  `expiration` int(11) NOT NULL,
  PRIMARY KEY (`key`),
  KEY `cache_expiration_index` (`expiration`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `cache_locks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `cache_locks` (
  `key` varchar(255) NOT NULL,
  `owner` varchar(255) NOT NULL,
  `expiration` int(11) NOT NULL,
  PRIMARY KEY (`key`),
  KEY `cache_locks_expiration_index` (`expiration`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `conversation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `conversation` (
  `CONV_ID` char(6) NOT NULL COMMENT 'Unique conversation ID',
  `CONV_CREATED_AT` datetime NOT NULL COMMENT 'Conversation start timestamp',
  `BUY_ID` char(6) NOT NULL COMMENT 'Buyer who initiated the conversation',
  `FMR_ID` char(6) NOT NULL COMMENT 'Farmer participating in conversation',
  PRIMARY KEY (`CONV_ID`),
  KEY `FK_CONVERSATION_BUYER` (`BUY_ID`),
  KEY `FK_CONVERSATION_FARMER` (`FMR_ID`),
  CONSTRAINT `FK_CONVERSATION_BUYER` FOREIGN KEY (`BUY_ID`) REFERENCES `buyer` (`BUY_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_CONVERSATION_FARMER` FOREIGN KEY (`FMR_ID`) REFERENCES `farmer` (`FMR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Conversations between buyers and farmers';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `crop_category`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `crop_category` (
  `CAT_ID` char(6) NOT NULL COMMENT 'Unique category ID',
  `CAT_NAME` varchar(100) NOT NULL COMMENT 'Category label',
  `CAT_ICON` varchar(200) DEFAULT NULL COMMENT 'Icon reference for crop category',
  `CAT_DESCRIPTION` varchar(300) DEFAULT NULL COMMENT 'Description of category',
  PRIMARY KEY (`CAT_ID`),
  UNIQUE KEY `UX_CATEGORY_NAME` (`CAT_NAME`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Crop categories/classification';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `failed_jobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `failed_jobs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(255) NOT NULL,
  `connection` text NOT NULL,
  `queue` text NOT NULL,
  `payload` longtext NOT NULL,
  `exception` longtext NOT NULL,
  `failed_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `failed_jobs_uuid_unique` (`uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `farm`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `farm` (
  `FRM_ID` char(6) NOT NULL COMMENT 'Unique farm identifier',
  `FRM_NAME` varchar(150) NOT NULL COMMENT 'Display name of the farm',
  `FRM_DESCRIPTION` text DEFAULT NULL COMMENT 'Brief farm description',
  `FRM_BARANGAY` varchar(100) NOT NULL COMMENT 'Barangay of the farm',
  `FRM_LATITUDE` decimal(10,8) NOT NULL COMMENT 'GPS latitude coordinate',
  `FRM_LONGITUDE` decimal(11,8) NOT NULL COMMENT 'GPS longitude coordinate',
  `FRM_PIN_ACTIVE` tinyint(1) NOT NULL DEFAULT 1 COMMENT 'Map visibility flag (0 or 1)',
  `FRM_CREATED_AT` datetime NOT NULL COMMENT 'Farm creation timestamp',
  `FMR_ID` char(6) NOT NULL COMMENT 'References the farmer owner',
  PRIMARY KEY (`FRM_ID`),
  KEY `FK_FARM_FARMER` (`FMR_ID`),
  CONSTRAINT `FK_FARM_FARMER` FOREIGN KEY (`FMR_ID`) REFERENCES `farmer` (`FMR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Farms owned by farmers';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `farm_photo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `farm_photo` (
  `FPHOTO_ID` char(6) NOT NULL COMMENT 'Unique photo record ID',
  `FPHOTO_FILE_PATH` varchar(500) NOT NULL COMMENT 'URL/path to farm photo',
  `FPHOTO_UPLOADED_AT` datetime NOT NULL COMMENT 'When photo was uploaded',
  `FRM_ID` char(6) NOT NULL COMMENT 'References the farm',
  PRIMARY KEY (`FPHOTO_ID`),
  KEY `FK_FARMPHOTO_FARM` (`FRM_ID`),
  CONSTRAINT `FK_FARMPHOTO_FARM` FOREIGN KEY (`FRM_ID`) REFERENCES `farm` (`FRM_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Photos belonging to a farm';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `farmer`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `farmer` (
  `FMR_ID` char(6) NOT NULL COMMENT 'Unique farmer identifier',
  `FMR_SELLER_MODE_ACTIVE` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'Whether seller mode is active (0 or 1)',
  `FMR_VERIFIED_AT` datetime DEFAULT NULL COMMENT 'Timestamp when farmer/seller setup was completed',
  `BUY_ID` char(6) NOT NULL COMMENT 'References the buyer account',
  PRIMARY KEY (`FMR_ID`),
  UNIQUE KEY `UX_FARMER_BUY` (`BUY_ID`),
  CONSTRAINT `FK_FARMER_BUYER` FOREIGN KEY (`BUY_ID`) REFERENCES `buyer` (`BUY_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Farmer/seller profile extension of BUYER';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `insight`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `insight` (
  `INS_ID` char(6) NOT NULL COMMENT 'Unique insight record ID',
  `INS_TITLE` varchar(200) NOT NULL COMMENT 'Title of the insight',
  `INS_CONTENT` text NOT NULL COMMENT 'Insight description/body',
  `INS_CREATED_AT` datetime NOT NULL COMMENT 'When insight was generated',
  `CAT_ID` char(6) NOT NULL COMMENT 'Crop category this insight is about',
  `SRCH_ID` char(6) NOT NULL COMMENT 'Search log that generated this insight',
  PRIMARY KEY (`INS_ID`),
  KEY `FK_INSIGHT_CATEGORY` (`CAT_ID`),
  KEY `FK_INSIGHT_SEARCHLOG` (`SRCH_ID`),
  CONSTRAINT `FK_INSIGHT_CATEGORY` FOREIGN KEY (`CAT_ID`) REFERENCES `crop_category` (`CAT_ID`) ON UPDATE CASCADE,
  CONSTRAINT `FK_INSIGHT_SEARCHLOG` FOREIGN KEY (`SRCH_ID`) REFERENCES `search_log` (`SRCH_ID`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Generated insights derived from search activity';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `job_batches`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `job_batches` (
  `id` varchar(255) NOT NULL,
  `name` varchar(255) NOT NULL,
  `total_jobs` int(11) NOT NULL,
  `pending_jobs` int(11) NOT NULL,
  `failed_jobs` int(11) NOT NULL,
  `failed_job_ids` longtext NOT NULL,
  `options` mediumtext DEFAULT NULL,
  `cancelled_at` int(11) DEFAULT NULL,
  `created_at` int(11) NOT NULL,
  `finished_at` int(11) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `jobs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `jobs` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `queue` varchar(255) NOT NULL,
  `payload` longtext NOT NULL,
  `attempts` tinyint(3) unsigned NOT NULL,
  `reserved_at` int(10) unsigned DEFAULT NULL,
  `available_at` int(10) unsigned NOT NULL,
  `created_at` int(10) unsigned NOT NULL,
  PRIMARY KEY (`id`),
  KEY `jobs_queue_index` (`queue`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `listing`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `listing` (
  `LST_ID` char(6) NOT NULL COMMENT 'Unique listing ID',
  `LST_CROP_ICON` varchar(200) DEFAULT NULL COMMENT 'Selected crop icon from library',
  `LST_STATUS` enum('AVAILABLE_NOW','SOON_TO_HARVEST','NOT_AVAILABLE') NOT NULL COMMENT 'Crop availability status',
  `LST_AVAILABILITY` enum('ACTIVE','NOT_AVAILABLE','REMOVED') NOT NULL COMMENT 'Admin listing state',
  `LST_HARVEST_DATE` date DEFAULT NULL COMMENT 'Expected harvest date',
  `LST_EXPIRY_DATE` datetime DEFAULT NULL COMMENT 'Auto-expiry date (3-day rule)',
  `LST_IMAGE` varchar(500) DEFAULT NULL COMMENT 'URL to crop image',
  `LST_CREATED_AT` datetime NOT NULL COMMENT 'Listing creation timestamp',
  `LST_UPDATED_AT` datetime NOT NULL COMMENT 'Last update timestamp',
  `FMR_ID` char(6) NOT NULL COMMENT 'Farmer who owns the listing',
  `FRM_ID` char(6) NOT NULL COMMENT 'Farm the listing belongs to',
  `CAT_ID` char(6) NOT NULL COMMENT 'Classifies crop category',
  PRIMARY KEY (`LST_ID`),
  KEY `FK_LISTING_FARMER` (`FMR_ID`),
  KEY `FK_LISTING_FARM` (`FRM_ID`),
  KEY `FK_LISTING_CATEGORY` (`CAT_ID`),
  CONSTRAINT `FK_LISTING_CATEGORY` FOREIGN KEY (`CAT_ID`) REFERENCES `crop_category` (`CAT_ID`) ON UPDATE CASCADE,
  CONSTRAINT `FK_LISTING_FARM` FOREIGN KEY (`FRM_ID`) REFERENCES `farm` (`FRM_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_LISTING_FARMER` FOREIGN KEY (`FMR_ID`) REFERENCES `farmer` (`FMR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Crop listings posted by farmers';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `message`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `message` (
  `MSG_ID` char(6) NOT NULL COMMENT 'Unique message ID',
  `MSG_CONTENT` text NOT NULL COMMENT 'Message text content',
  `MSG_CREATED_AT` datetime NOT NULL COMMENT 'Timestamp message was sent',
  `CONV_ID` char(6) NOT NULL COMMENT 'Conversation this message belongs to',
  `USR_ID` char(6) NOT NULL COMMENT 'User who sent the message',
  PRIMARY KEY (`MSG_ID`),
  KEY `FK_MESSAGE_CONVERSATION` (`CONV_ID`),
  KEY `FK_MESSAGE_USER` (`USR_ID`),
  CONSTRAINT `FK_MESSAGE_CONVERSATION` FOREIGN KEY (`CONV_ID`) REFERENCES `conversation` (`CONV_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_MESSAGE_USER` FOREIGN KEY (`USR_ID`) REFERENCES `user` (`USR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Individual messages within a conversation';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `migrations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `migrations` (
  `id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `migration` varchar(255) NOT NULL,
  `batch` int(11) NOT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `report`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `report` (
  `RPT_ID` int(11) NOT NULL AUTO_INCREMENT,
  `LST_ID` char(6) NOT NULL,
  `USR_ID` char(6) NOT NULL,
  `RPT_REASON` varchar(255) NOT NULL,
  `RPT_STATUS` enum('New','Reviewing','Resolved','Dismissed') DEFAULT 'New',
  `RPT_CREATED_AT` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`RPT_ID`),
  KEY `FK_REPORT_LISTING` (`LST_ID`),
  KEY `FK_REPORT_USER` (`USR_ID`),
  CONSTRAINT `FK_REPORT_LISTING` FOREIGN KEY (`LST_ID`) REFERENCES `listing` (`LST_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_REPORT_USER` FOREIGN KEY (`USR_ID`) REFERENCES `user` (`USR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `search_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `search_log` (
  `SRCH_ID` char(6) NOT NULL COMMENT 'Unique search log ID',
  `SRCH_KEYWORD` varchar(200) DEFAULT NULL COMMENT 'Keyword entered by user',
  `SRCH_FILTERS` varchar(300) DEFAULT NULL COMMENT 'Filters applied during search',
  `SRCH_CREATED_AT` datetime NOT NULL COMMENT 'When search was performed',
  `USR_ID` char(6) NOT NULL COMMENT 'User who performed the search',
  PRIMARY KEY (`SRCH_ID`),
  KEY `FK_SEARCHLOG_USER` (`USR_ID`),
  CONSTRAINT `FK_SEARCHLOG_USER` FOREIGN KEY (`USR_ID`) REFERENCES `user` (`USR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Log of user search activity';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `trend`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `trend` (
  `TRND_ID` char(6) NOT NULL COMMENT 'Unique trend record ID',
  `TRND_TITLE` varchar(200) NOT NULL COMMENT 'Title of the trend',
  `TRND_DATA` text NOT NULL COMMENT 'Trend data / analysis results',
  `TRND_CREATED_AT` datetime NOT NULL COMMENT 'When trend was generated',
  `TRND_PERIOD_MONTH` char(7) NOT NULL COMMENT 'Month this trend covers (YYYY-MM)',
  `CAT_ID` char(6) NOT NULL COMMENT 'Crop category this trend is about',
  PRIMARY KEY (`TRND_ID`),
  KEY `FK_TREND_CATEGORY` (`CAT_ID`),
  CONSTRAINT `FK_TREND_CATEGORY` FOREIGN KEY (`CAT_ID`) REFERENCES `crop_category` (`CAT_ID`) ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Monthly crop trend analysis records';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `user`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `user` (
  `USR_ID` char(6) NOT NULL COMMENT 'Unique user identifier',
  `USR_NAME` varchar(150) NOT NULL COMMENT 'Full registered name',
  `USR_EMAIL` varchar(200) NOT NULL COMMENT 'Email address',
  `USR_PASSWORD` varchar(255) NOT NULL COMMENT 'Hashed password (bcrypt)',
  `USR_MOBILE_NUMBER` varchar(20) NOT NULL COMMENT 'Mobile contact number',
  `USR_ROLE` enum('GENERAL_USER','ADMIN') NOT NULL COMMENT 'System role',
  `USR_IS_SELLER` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'Seller mode flag (0 or 1)',
  `USR_STATUS` enum('ACTIVE','PENDING_VERIFICATION','DEACTIVATED') NOT NULL COMMENT 'Account state',
  `USR_CREATED_AT` datetime NOT NULL COMMENT 'Account creation timestamp',
  PRIMARY KEY (`USR_ID`),
  UNIQUE KEY `UX_USER_EMAIL` (`USR_EMAIL`),
  UNIQUE KEY `UX_USER_MOBILE` (`USR_MOBILE_NUMBER`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='System user accounts';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `whitelist`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `whitelist` (
  `WLST_ID` char(6) NOT NULL COMMENT 'Unique whitelist record ID',
  `WLST_MOBILE_NUMBER` varchar(20) NOT NULL COMMENT 'Pre-approved mobile number',
  `WLST_IS_ACTIVE` tinyint(1) NOT NULL DEFAULT 1 COMMENT 'Authorization status flag (0 or 1)',
  `WLST_ADDED_AT` datetime NOT NULL COMMENT 'When number was added',
  `USR_ADDED_ID` char(6) NOT NULL COMMENT 'Admin who added the number',
  `USR_DEACTIVATED_ID` char(6) DEFAULT NULL COMMENT 'Admin who deactivated the number',
  PRIMARY KEY (`WLST_ID`),
  UNIQUE KEY `UX_WHITELIST_MOBILE` (`WLST_MOBILE_NUMBER`),
  KEY `FK_WHITELIST_ADDED_BY` (`USR_ADDED_ID`),
  KEY `FK_WHITELIST_DEACTIVATED_BY` (`USR_DEACTIVATED_ID`),
  CONSTRAINT `FK_WHITELIST_ADDED_BY` FOREIGN KEY (`USR_ADDED_ID`) REFERENCES `user` (`USR_ID`) ON UPDATE CASCADE,
  CONSTRAINT `FK_WHITELIST_DEACTIVATED_BY` FOREIGN KEY (`USR_DEACTIVATED_ID`) REFERENCES `user` (`USR_ID`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Pre-approved mobile numbers whitelist';
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (1,'0001_01_01_000000_create_users_table',1);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (2,'0001_01_01_000001_create_cache_table',1);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (3,'0001_01_01_000002_create_jobs_table',1);
