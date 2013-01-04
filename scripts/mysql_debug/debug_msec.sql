delimiter $$

-- mysql stored procedure debug helper
-- chetan sarva <csarva@operative.com> 2007-04-19
--
-- how to use this stuff:
--
-- import this file. it creates a database and associated stored procs
-- 
-- for timing your procedures:
--
-- call debug.on('my_identifier');
-- call .... [ code to profile ]
-- call debug.off('my_identifier');
--
-- for general debug messages
-- call debug.msg('my_identifier', 'debug message');
-- or 
-- call debug.msg('my_identifier', my_variable);
-- or
-- call debug.msg('my_identifier', @my_var);

DROP DATABASE IF EXISTS `debug`;
CREATE DATABASE `debug`;
USE `debug`;

DROP TABLE IF EXISTS `debug`;
CREATE TABLE `debug` (
  `id` int(11) NOT NULL auto_increment,
  `proc_id` varchar(100) default NULL,
  `debug_output` text,
  `ts` char(23) NOT NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

DROP PROCEDURE IF EXISTS `debug`.`on` $$
CREATE PROCEDURE `on`(in p_proc_id varchar(100))
begin
  call debug.msg(p_proc_id,'start');
end $$

DROP PROCEDURE IF EXISTS `debug`.`msg` $$
CREATE PROCEDURE `msg`(in p_proc_id varchar(100),in p_debug_info text)
begin
  insert into debug (proc_id,debug_output, ts)
    values (p_proc_id,p_debug_info, now_msec());
end $$

DROP PROCEDURE IF EXISTS `debug`.`off` $$
CREATE PROCEDURE `off`(in p_proc_id varchar(100))
begin
  call debug.msg(p_proc_id,'end');
end $$

delimiter ;
