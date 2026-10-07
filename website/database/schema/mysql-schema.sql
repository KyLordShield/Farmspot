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
DROP TABLE IF EXISTS `contact_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `contact_log` (
  `CTL_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `USR_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `LST_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `CTL_METHOD` enum('CALL','SMS') NOT NULL,
  `CTL_CREATED_AT` datetime NOT NULL,
  PRIMARY KEY (`CTL_ID`),
  KEY `FK_CONTACTLOG_USER` (`USR_ID`),
  KEY `FK_CONTACTLOG_LISTING` (`LST_ID`),
  CONSTRAINT `contact_log_lst_id_foreign` FOREIGN KEY (`LST_ID`) REFERENCES `listing` (`LST_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `contact_log_usr_id_foreign` FOREIGN KEY (`USR_ID`) REFERENCES `user` (`USR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `conversation`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `conversation` (
  `CONV_ID` char(6) NOT NULL COMMENT 'Unique conversation ID',
  `LST_ID` char(6) DEFAULT NULL,
  `CONV_CREATED_AT` datetime NOT NULL COMMENT 'Conversation start timestamp',
  `BUY_ID` char(6) NOT NULL COMMENT 'Buyer who initiated the conversation',
  `FMR_ID` char(6) NOT NULL COMMENT 'Farmer participating in conversation',
  `FRM_ID` char(6) DEFAULT NULL,
  `CNV_LAST_MESSAGE` varchar(500) DEFAULT NULL,
  `CNV_LAST_MESSAGE_AT` datetime DEFAULT NULL,
  PRIMARY KEY (`CONV_ID`),
  UNIQUE KEY `UNQ_CONVERSATION_LISTING_BUYER` (`LST_ID`,`BUY_ID`),
  KEY `FK_CONVERSATION_BUYER` (`BUY_ID`),
  KEY `FK_CONVERSATION_FARMER` (`FMR_ID`),
  KEY `FK_CONVERSATION_LISTING` (`LST_ID`),
  KEY `FK_CONVERSATION_FARM` (`FRM_ID`),
  KEY `IDX_CONVERSATION_LAST_ACTIVITY` (`CNV_LAST_MESSAGE_AT`),
  CONSTRAINT `FK_CONVERSATION_BUYER` FOREIGN KEY (`BUY_ID`) REFERENCES `buyer` (`BUY_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_CONVERSATION_FARMER` FOREIGN KEY (`FMR_ID`) REFERENCES `farmer` (`FMR_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `conversation_frm_id_foreign` FOREIGN KEY (`FRM_ID`) REFERENCES `farm` (`FRM_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `conversation_lst_id_foreign` FOREIGN KEY (`LST_ID`) REFERENCES `listing` (`LST_ID`) ON DELETE CASCADE ON UPDATE CASCADE
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
  `FRM_STATUS` enum('PENDING_REVIEW','APPROVED','REJECTED','ARCHIVED') NOT NULL DEFAULT 'PENDING_REVIEW',
  `FRM_CREATED_AT` datetime NOT NULL COMMENT 'Farm creation timestamp',
  `FRM_VERIFICATION_DOC_PATH` varchar(500) DEFAULT NULL,
  `FRM_FARM_CERTIFICATE_PATH` varchar(500) DEFAULT NULL,
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
  `FPHOTO_IS_PRIMARY` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'Whether this photo is the farm cover (0 or 1)',
  `FRM_ID` char(6) NOT NULL COMMENT 'References the farm',
  PRIMARY KEY (`FPHOTO_ID`),
  KEY `FK_FARMPHOTO_FARM` (`FRM_ID`),
  CONSTRAINT `FK_FARMPHOTO_FARM` FOREIGN KEY (`FRM_ID`) REFERENCES `farm` (`FRM_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Photos belonging to a farm';
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `farm_visit_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `farm_visit_log` (
  `FVL_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `USR_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `FRM_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `FVL_CREATED_AT` datetime NOT NULL,
  PRIMARY KEY (`FVL_ID`),
  KEY `FK_FARMVISITLOG_USER` (`USR_ID`),
  KEY `FK_FARMVISITLOG_FARM` (`FRM_ID`),
  CONSTRAINT `farm_visit_log_frm_id_foreign` FOREIGN KEY (`FRM_ID`) REFERENCES `farm` (`FRM_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `farm_visit_log_usr_id_foreign` FOREIGN KEY (`USR_ID`) REFERENCES `user` (`USR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
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
  `CAT_ID` char(6) DEFAULT NULL,
  `SRCH_ID` char(6) DEFAULT NULL,
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
  `LST_DESCRIPTION` text DEFAULT NULL,
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
DROP TABLE IF EXISTS `listing_photo`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `listing_photo` (
  `LPHOTO_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `LPHOTO_FILE_PATH` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `LPHOTO_UPLOADED_AT` datetime NOT NULL,
  `LPHOTO_IS_PRIMARY` tinyint(1) NOT NULL DEFAULT 0,
  `LST_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  PRIMARY KEY (`LPHOTO_ID`),
  KEY `FK_LISTINGPHOTO_LISTING` (`LST_ID`),
  CONSTRAINT `listing_photo_lst_id_foreign` FOREIGN KEY (`LST_ID`) REFERENCES `listing` (`LST_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `message`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `message` (
  `MSG_ID` char(6) NOT NULL COMMENT 'Unique message ID',
  `MSG_SEQ` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
`MSG_CONTENT` text NOT NULL COMMENT 'Message text content',
  `MSG_IMAGE_PATH` varchar(500) DEFAULT NULL COMMENT 'Cloudinary URL of the photo this message carries, null for a text-only message',
  `MSG_VISIBILITY` enum('VISIBLE','HIDDEN') NOT NULL DEFAULT 'VISIBLE' COMMENT 'HIDDEN by a moderator after a report. Rows are kept so the action can be undone and the history stays auditable.',
  `MSG_HIDDEN_AT` datetime DEFAULT NULL COMMENT 'When it was hidden, for the audit trail.',
  `MSG_IS_READ` tinyint(1) NOT NULL DEFAULT 0,
  `MSG_CREATED_AT` datetime NOT NULL COMMENT 'Timestamp message was sent',
  `CONV_ID` char(6) NOT NULL COMMENT 'Conversation this message belongs to',
  `USR_ID` char(6) NOT NULL COMMENT 'User who sent the message',
  PRIMARY KEY (`MSG_ID`),
  UNIQUE KEY `UNQ_MESSAGE_SEQ` (`MSG_SEQ`),
  KEY `FK_MESSAGE_CONVERSATION` (`CONV_ID`),
  KEY `FK_MESSAGE_USER` (`USR_ID`),
  KEY `IDX_MESSAGE_CONVERSATION_SEQ` (`CONV_ID`,`MSG_SEQ`),
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
DROP TABLE IF EXISTS `notification`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `notification` (
  `NOTIF_ID` char(6) NOT NULL COMMENT 'Unique notification ID',
  `USR_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL COMMENT 'User the notification is addressed to',
  `NOTIF_TYPE` enum('LISTING_EXPIRING_SOON','LISTING_EXPIRED','LISTING_REMOVED','SELLER_DEACTIVATED','ACCOUNT_SUSPENDED','ACCOUNT_REACTIVATED','REPORT_UPDATE','HARVEST_REMINDER','SETUP_COMPLETE','WHITELIST_APPROVED','SELLER_REACTIVATED') NOT NULL COMMENT 'What happened: listing expiring/expired/removed, seller or account change, report outcome, harvest reminder, setup finished, whitelist approval, seller reactivation',
  `NOTIF_TITLE` varchar(150) NOT NULL COMMENT 'Short headline shown in the notification list',
  `NOTIF_BODY` varchar(300) NOT NULL COMMENT 'One short sentence of plain language for the farmer or buyer',
  `NOTIF_REF_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL COMMENT 'Related record id (e.g. LST_ID) used for deep-linking and to avoid telling the user twice',
  `NOTIF_IS_READ` tinyint(1) NOT NULL DEFAULT 0 COMMENT 'Whether the user has opened it (0 or 1)',
  `NOTIF_CREATED_AT` datetime NOT NULL COMMENT 'When the notification was created',
  PRIMARY KEY (`NOTIF_ID`),
  KEY `IDX_NOTIFICATION_USER_READ` (`USR_ID`,`NOTIF_IS_READ`),
  KEY `IDX_NOTIFICATION_TYPE_REF` (`NOTIF_TYPE`,`NOTIF_REF_ID`),
  CONSTRAINT `FK_NOTIFICATION_USER` FOREIGN KEY (`USR_ID`) REFERENCES `user` (`USR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `notifications`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `notifications` (
  `id` char(36) NOT NULL,
  `type` varchar(255) NOT NULL,
  `notifiable_type` varchar(255) NOT NULL,
  `notifiable_id` char(6) NOT NULL,
  `data` text NOT NULL,
  `read_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `notifications_notifiable_type_notifiable_id_index` (`notifiable_type`,`notifiable_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `personal_access_tokens`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `personal_access_tokens` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `tokenable_type` varchar(255) NOT NULL,
  `tokenable_id` varchar(6) NOT NULL,
  `name` text NOT NULL,
  `token` varchar(64) NOT NULL,
  `abilities` text DEFAULT NULL,
  `last_used_at` timestamp NULL DEFAULT NULL,
  `expires_at` timestamp NULL DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT NULL,
  `updated_at` timestamp NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `personal_access_tokens_token_unique` (`token`),
  KEY `personal_access_tokens_tokenable_type_tokenable_id_index` (`tokenable_type`,`tokenable_id`),
  KEY `personal_access_tokens_expires_at_index` (`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `report`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `report` (
  `RPT_ID` char(6) NOT NULL,
  `LST_ID` char(6) DEFAULT NULL,
  `USR_ID` char(6) NOT NULL,
  `RPT_REASON` varchar(255) NOT NULL,
  `RPT_STATUS` enum('New','Reviewing','Resolved','Dismissed') DEFAULT 'New',
  `RPT_CREATED_AT` datetime NOT NULL DEFAULT current_timestamp(),
  `RPT_TARGET_TYPE` enum('LISTING','MESSAGE','FARMER','USER') NOT NULL DEFAULT 'LISTING' COMMENT 'What was reported: a crop listing, a chat message, a farmer/seller account, or a plain user account.',
  `RPT_TARGET_ID` char(6) DEFAULT NULL COMMENT 'Primary key of the reported thing in its own table: LST_ID, MSG_ID, FMR_ID or USR_ID. No foreign key, since it spans four tables.',
  `RPT_REASON_CODE` enum('MISLEADING_INFO','FAKE_LISTING','HARASSMENT','INAPPROPRIATE_CONTENT','FRAUD_OR_SCAM','SPAM','UNSAFE_BEHAVIOR','OTHER') NOT NULL DEFAULT 'OTHER' COMMENT 'The taxonomy value. RPT_REASON keeps the human-readable label for the existing admin search and tables.',
  `RPT_DETAILS` text DEFAULT NULL COMMENT 'Optional free text the reporter typed in the app.',
  `RPT_UPDATED_AT` datetime DEFAULT NULL COMMENT 'When a moderator last changed the status, for "how long has this been open".',
  PRIMARY KEY (`RPT_ID`),
  KEY `FK_REPORT_LISTING` (`LST_ID`),
  KEY `FK_REPORT_USER` (`USR_ID`),
  KEY `FK_REPORT_TARGET_TYPE` (`RPT_TARGET_TYPE`),
  KEY `FK_REPORT_TARGET_ID` (`RPT_TARGET_ID`),
  KEY `IDX_REPORT_STATUS_CREATED` (`RPT_STATUS`,`RPT_CREATED_AT`),
  CONSTRAINT `FK_REPORT_LISTING` FOREIGN KEY (`LST_ID`) REFERENCES `listing` (`LST_ID`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `FK_REPORT_USER` FOREIGN KEY (`USR_ID`) REFERENCES `user` (`USR_ID`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
DROP TABLE IF EXISTS `report_action`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `report_action` (
  `RAC_ID` char(6) NOT NULL,
  `RAC_SEQ` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `RPT_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci NOT NULL,
  `RAC_ACTION` varchar(40) NOT NULL,
  `RAC_SUBJECT_TYPE` varchar(20) NOT NULL DEFAULT 'LISTING',
  `RAC_SUBJECT_ID` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `RAC_PREV` text DEFAULT NULL,
  `RAC_NOTE` text DEFAULT NULL,
  `RAC_BY` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  `RAC_APPLIED_AT` datetime(6) NOT NULL,
  `RAC_REVERTED_AT` datetime(6) DEFAULT NULL,
  `RAC_REVERTED_BY` char(6) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`RAC_ID`),
  KEY `report_action_rpt_id_index` (`RPT_ID`),
  KEY `IDX_ACTION_LIVE` (`RPT_ID`,`RAC_REVERTED_AT`),
  KEY `IDX_ACTION_SEQ` (`RAC_SEQ`),
  CONSTRAINT `report_action_rpt_id_foreign` FOREIGN KEY (`RPT_ID`) REFERENCES `report` (`RPT_ID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
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
  `CAT_ID` char(6) DEFAULT NULL,
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
  `USR_ADDRESS` varchar(255) DEFAULT NULL,
  `USR_PHOTO_PATH` varchar(500) DEFAULT NULL,
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
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (5,'2026_08_30_140207_create_personal_access_tokens_table',2);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (6,'2026_09_02_053007_add_frm_verification_doc_path_to_farm_table',3);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (7,'2026_09_02_175011_add_frm_status_to_farm_table',4);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (8,'2026_09_06_000001_create_farm_visit_log_table',5);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (9,'2026_09_06_000002_create_contact_log_table',5);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (10,'2026_09_17_000001_create_listing_photo_table',6);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (11,'2026_09_17_000002_add_lst_description_to_listing_table',6);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (12,'2026_09_19_000001_add_usr_address_and_photo_path_to_user_table',7);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (13,'2026_09_26_000001_add_frm_farm_certificate_path_to_farm_table',8);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (14,'2026_09_26_000002_add_messaging_fields_to_conversation_table',9);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (15,'2026_09_26_000003_add_messaging_fields_to_message_table',9);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (16,'2026_09_27_000004_add_msg_seq_to_message_table',10);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (17,'2026_09_30_000001_add_archived_to_frm_status_enum',11);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (18,'2026_09_30_000002_add_targets_to_report_table',11);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (19,'2026_10_01_000003_add_action_to_report_table',11);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (20,'2026_10_01_000004_change_report_id_to_six_digits',12);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (21,'2026_10_01_000005_create_report_action_table',13);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (22,'2026_10_01_000006_add_visibility_to_message_table',13);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (23,'2026_10_01_000007_create_notifications_table',13);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (24,'2026_10_01_000008_drop_action_columns_from_report_table',13);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (25,'2026_10_01_000009_add_microseconds_to_report_action_timestamps',14);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (26,'2026_10_01_000010_add_sequence_to_report_action_table',14);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (28,'2026_10_02_000001_create_notification_table',15);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (29,'2026_10_03_000001_add_whitelist_and_reactivation_notification_types',16);
INSERT INTO `migrations` (`id`, `migration`, `batch`) VALUES (30,'2026_10_07_000001_add_msg_image_path_to_message_table',20);
