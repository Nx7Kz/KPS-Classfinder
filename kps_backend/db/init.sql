
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `kps_classfinder` /*!40100 DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci */ /*!80016 DEFAULT ENCRYPTION='N' */;

USE `kps_classfinder`;
DROP TABLE IF EXISTS `buildings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `buildings` (
  `id` int NOT NULL AUTO_INCREMENT,
  `code` varchar(20) NOT NULL,
  `name` varchar(255) NOT NULL,
  `description` text,
  `location` varchar(255) DEFAULT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_buildings_code` (`code`),
  UNIQUE KEY `uq_buildings_name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

LOCK TABLES `buildings` WRITE;
/*!40000 ALTER TABLE `buildings` DISABLE KEYS */;
INSERT INTO `buildings` VALUES (3,'LH3','อาคารเรียนรวม 3 (ศร.3)',NULL,NULL,'2026-09-18 18:49:58'),(4,'KH','อาคารเรียน 80 ปี',NULL,NULL,'2026-09-18 18:49:58');
/*!40000 ALTER TABLE `buildings` ENABLE KEYS */;
UNLOCK TABLES;
DROP TABLE IF EXISTS `rooms`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `rooms` (
  `id` int NOT NULL AUTO_INCREMENT,
  `room_code` varchar(255) NOT NULL,
  `building_id` int NOT NULL,
  `floor` varchar(50) DEFAULT '-',
  `room_type` varchar(50) DEFAULT NULL,
  `capacity` int DEFAULT NULL,
  `status` enum('active','maintenance') NOT NULL DEFAULT 'active',
  `amenities` json DEFAULT NULL,
  `pin_x` decimal(6,3) DEFAULT NULL,
  `pin_y` decimal(6,3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_rooms_building` (`building_id`),
  CONSTRAINT `fk_rooms_building` FOREIGN KEY (`building_id`) REFERENCES `buildings` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=52 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

LOCK TABLES `rooms` WRITE;
/*!40000 ALTER TABLE `rooms` DISABLE KEYS */;
INSERT INTO `rooms` VALUES (1,'ห้องประชุมใหญ่',3,'1',NULL,NULL,'active',NULL,49.569,28.571),(2,'ห้องประชุมกลาง',3,'1',NULL,NULL,'active',NULL,36.207,29.503),(3,'ห้องทะเบียน',3,'1',NULL,NULL,'active',NULL,49.353,46.586),(4,'e-Service',3,'1',NULL,NULL,'active',NULL,49.784,74.230),(5,'สำนักงาน',3,'1',NULL,NULL,'active',NULL,64.655,38.199),(6,'ห้องธุรการ',3,'1',NULL,NULL,'active',NULL,64.655,53.730),(7,'ห้องผลิตสื่อการเรียนการสอน',3,'1',NULL,NULL,'active',NULL,35.345,38.510),(8,'โสตทัศนศึกษา',3,'1',NULL,NULL,'active',NULL,35.345,44.412),(9,'Service+CCTV',3,'1',NULL,NULL,'active',NULL,35.129,54.661),(10,'การศึกษาทั่วไป',3,'1',NULL,NULL,'active',NULL,34.483,61.184),(11,'ร้านค้า',3,'1',NULL,NULL,'active',NULL,49.784,79.510),(12,'LH3-201',3,'2',NULL,NULL,'active',NULL,62.716,76.468),(13,'LH3-202',3,'2',NULL,NULL,'active',NULL,62.284,72.057),(14,'LH3-203',3,'2',NULL,NULL,'active',NULL,38.793,72.057),(15,'LH3-204',3,'2',NULL,NULL,'active',NULL,38.578,76.153),(16,'LH3-205',3,'2',NULL,NULL,'active',NULL,32.112,63.866),(17,'LH3-206',3,'2',NULL,NULL,'active',NULL,28.017,64.181),(18,'LH3-207',3,'2',NULL,NULL,'active',NULL,28.879,32.989),(19,'LH3-208',3,'2',NULL,NULL,'active',NULL,31.897,32.674),(20,'LH3-209',3,'2',NULL,NULL,'active',NULL,38.793,22.591),(21,'LH3-210',3,'2',NULL,NULL,'active',NULL,62.716,23.222),(22,'LH3-211',3,'2',NULL,NULL,'active',NULL,68.750,47.797),(23,'LH3-301',3,'3',NULL,NULL,'active',NULL,46.552,72.139),(24,'LH3-302',3,'3',NULL,NULL,'active',NULL,26.293,51.537),(25,'LH3-303',3,'3',NULL,NULL,'active',NULL,34.914,26.324),(26,'LH3-304',3,'3',NULL,NULL,'active',NULL,59.267,26.016),(27,'LH3-305',3,'3',NULL,NULL,'active',NULL,68.103,35.548),(28,'LH3-306',3,'3',NULL,NULL,'active',NULL,64.871,67.527),(29,'LH3-307',3,'3',NULL,NULL,'active',NULL,70.259,68.142),(31,'ห้องรับรอง',4,'1',NULL,NULL,'active',NULL,NULL,NULL),(32,'ร้านค้า',4,'1',NULL,NULL,'active',NULL,NULL,NULL),(33,'KH-201',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(34,'KH-202',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(35,'KH-203',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(36,'KH-204',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(37,'KH-205',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(38,'KH-206',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(39,'KH-207',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(40,'KH-208',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(41,'ห้องเจ้าหน้าที่',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(42,'ห้องประชุม',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(43,'ห้องละหมาด',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(44,'ห้องพักอาจารย์',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(45,'ห้องรับรอง',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(46,'หอประชุม จงรัก วัชรินทร์รัตน์',4,'2',NULL,NULL,'active',NULL,NULL,NULL),(47,'CO-WORKING SPACE',4,'2',NULL,NULL,'active',NULL,NULL,NULL);
/*!40000 ALTER TABLE `rooms` ENABLE KEYS */;
UNLOCK TABLES;
-- ==========================================================
-- Dashboard tables: floor plans, 360 panoramas, activity logs, admin settings
-- ==========================================================
DROP TABLE IF EXISTS `floor_plans`;
CREATE TABLE `floor_plans` (
  `id` int NOT NULL AUTO_INCREMENT,
  `building_id` int NOT NULL,
  `floor` varchar(50) NOT NULL,
  `image_url` varchar(500) NOT NULL,
  `width` int NOT NULL,
  `height` int NOT NULL,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_floor_plans_building_floor` (`building_id`,`floor`),
  CONSTRAINT `fk_floor_plans_building` FOREIGN KEY (`building_id`) REFERENCES `buildings` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `floor_plans` (`building_id`, `floor`, `image_url`, `width`, `height`)
SELECT id, '1', '/floorplans/lh3-floor-1.png', 1506, 1045 FROM `buildings` WHERE code = 'LH3';
INSERT INTO `floor_plans` (`building_id`, `floor`, `image_url`, `width`, `height`)
SELECT id, '2', '/floorplans/lh3-floor-2.png', 1516, 1037 FROM `buildings` WHERE code = 'LH3';
INSERT INTO `floor_plans` (`building_id`, `floor`, `image_url`, `width`, `height`)
SELECT id, '3', '/floorplans/lh3-floor-3.png', 1498, 1050 FROM `buildings` WHERE code = 'LH3';

DROP TABLE IF EXISTS `panorama_hotspots`;
DROP TABLE IF EXISTS `panoramas`;
CREATE TABLE `panoramas` (
  `id` int NOT NULL AUTO_INCREMENT,
  `room_id` int NOT NULL,
  `image_url` varchar(500) NOT NULL,
  `position_label` varchar(100) DEFAULT NULL,
  `sort_order` int NOT NULL DEFAULT '0',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `fk_panoramas_room` (`room_id`),
  CONSTRAINT `fk_panoramas_room` FOREIGN KEY (`room_id`) REFERENCES `rooms` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `panorama_hotspots` (
  `id` int NOT NULL AUTO_INCREMENT,
  `panorama_id` int NOT NULL,
  `target_panorama_id` int DEFAULT NULL,
  `yaw` decimal(7,3) NOT NULL,
  `pitch` decimal(7,3) NOT NULL,
  `icon_type` varchar(30) NOT NULL DEFAULT 'arrow',
  `label` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `fk_hotspots_panorama` (`panorama_id`),
  KEY `fk_hotspots_target` (`target_panorama_id`),
  CONSTRAINT `fk_hotspots_panorama` FOREIGN KEY (`panorama_id`) REFERENCES `panoramas` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_hotspots_target` FOREIGN KEY (`target_panorama_id`) REFERENCES `panoramas` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

DROP TABLE IF EXISTS `activity_logs`;
CREATE TABLE `activity_logs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `action` varchar(30) NOT NULL,
  `entity` varchar(30) NOT NULL,
  `entity_id` int DEFAULT NULL,
  `detail` varchar(500) DEFAULT NULL,
  `username` varchar(100) DEFAULT NULL,
  `ip` varchar(64) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_activity_logs_created` (`created_at`),
  KEY `idx_activity_logs_entity_action` (`entity`,`action`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

DROP TABLE IF EXISTS `admin_settings`;
CREATE TABLE `admin_settings` (
  `setting_key` varchar(50) NOT NULL,
  `setting_value` text NOT NULL,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

