#include <my_global.h>
#include <my_sys.h>
#include <mysql.h>

#include <stdio.h>
#include <sys/time.h>
#include <time.h>
#include <unistd.h>

/*

 Copyright (c) 2006 Wadimoff <wadimoff@yahoo.com>                           
 Created:  27 April 2006                                                    

 NOW_MSEC() returns a character string representing the current date and time
 with milliseconds in format YYYY-MM-DD HH:MM:SS.mmm  e.g.: 2006-04-27 17:10:52.129

 How to install:
 #1  gcc -fPIC -shared -o mysql_now_msec.so mysql_now_msec.cc -I /usr/include/mysql

 #2  cp mysql_now_msec.so /usr/lib
     Comment : you can copy this wherever you want in the LD path

     or, for MySQL 5.1:
     sudo mkdir -p /usr/lib/mysql/plugin && sudo cp mysql_now_msec.so /usr/lib/mysql/plugin/

 #3  Run this query :                                                         
     CREATE FUNCTION now_msec RETURNS STRING SONAME "mysql_now_msec.so";

 #4  Run this query to test it:                                               

     SELECT NOW_MSEC();                                                       
     It should return something like that                                     
                                                                            
 mysql> select NOW_MSEC();                                                    
 +-------------------------+                                                  
 | NOW_MSEC()              |                                                  
 +-------------------------+                                                  
 | 2006-04-28 09:46:13.906 |                                                  
 +-------------------------+                                                  
 1 row in set (0.01 sec)                                                      

*/

extern "C" {
   my_bool now_msec_init(UDF_INIT *initid, UDF_ARGS *args, char *message);
   char *now_msec(
               UDF_INIT *initid,
               UDF_ARGS *args,
               char *result,
               unsigned long *length, char *is_null, char *error);
}

my_bool now_msec_init(UDF_INIT *initid, UDF_ARGS *args, char *message) {
   return 0;
}

char *now_msec(UDF_INIT *initid, UDF_ARGS *args, char *result,
               unsigned long *length, char *is_null, char *error) {

  struct timeval tv;
  struct tm* ptm;
  char time_string[20]; /* e.g. "2006-04-27 17:10:52" */
  long milliseconds;
  char *msec_time_string = result;
  time_t t;

  /* Obtain the time of day, and convert it to a tm struct. */
  gettimeofday (&tv, NULL);

  t = (time_t)tv.tv_sec;
  ptm = localtime (&t);   /* ptm = localtime (&tv.tv_sec); */

  /* Format the date and time, down to a single second.  */
  strftime (time_string, sizeof (time_string), "%Y-%m-%d %H:%M:%S", ptm);

  /* Compute milliseconds from microseconds. */
  milliseconds = tv.tv_usec / 1000;

  /* Print the formatted time, in seconds, followed by a decimal point
     and the milliseconds.  */
  sprintf(msec_time_string, "%s.%03ld\n", time_string, milliseconds);

  /* Hint: http://www.mysql.ru/docs/man/UDF_return_values.html */

  *length = 23;

  return(msec_time_string);
  
}
