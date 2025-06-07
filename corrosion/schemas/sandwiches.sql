CREATE TABLE sw (pk TEXT PRIMARY KEY NOT NULL DEFAULT '', sandwich TEXT);
CREATE TABLE sandwich_services (
  vm_id TEXT PRIMARY KEY NOT NULL DEFAULT '', 
  region TEXT, 
  srv_state TEXT,
  sandwich_addr TEXT, 
  sandwich TEXT,
  timestmp TEXT);