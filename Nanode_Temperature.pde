// Nanode graphing and logging
// July 2, 2012
//
// 07/06/12  working, would not DHCP on Comcast router (surprising-not!)
// 07/07/12  First commit to git


#define NANODE                                           // set this define if using a Nanode
//#define DHCP                                             // set this define to use DHCP
#define DEBUG                                            // set this define for debuggy goodness


#include "Wire.h"                                        // include I2C libraries
#include <LibTemperature.h>                              // include TMP421 libraries
#include <EtherCard.h>                                   // include the ethercard library
#include <SPI.h>                                         // necessary for the Si4735 lib
#ifdef NANODE
  #include <NanodeMAC.h>                                 // if its a NANODE5, include MAC reading
#endif


//**************************************
//**** BEGIN USER DEFINED VARIABLES ****
//**************************************
#define POST_RATE 60000                                  // rate to post to the db milliseconds (60 seconds)
#define UPDATE_RATE 5000                                 // rate to read the RSSI milliseconds (5 seconds)
float setpoint = 70.00;                                  // default setpoint upon first use
float differential = 2.50;                               // differential
char HOSTNAME[] PROGMEM = "ka1kjz.com";                  // hostname of a shared hosting server here
static byte hisip[] = {173,203,204,206};                 // ipaddress of the server here  
#define HTTPPATH "/php_db/wsah_temp.php"                 // path to the PHP script
#define DATABASE "wsah"                                  // database name
#define TABLE "temperature"                              // table name
//**********************************
//*** END USER DEFINED VARIABLES ***
//**********************************


//**********************************************************
//*** Sets the unique mac address for the ethernet board ***
//*** set this according to your network!!!              ***
//**********************************************************
#ifdef NANODE
  static byte mymac[] = {0,0,0,0,0,0};                   // left blank for Nanode5
#else
  static byte mymac[] = {0x54,0x55,0x58,0x12,0x34,0x56}; // make this unique on your network
#endif

#ifdef DHCP
  static byte myip[] = {0,0,0,0};                        // left blank for DHCP
  static byte gwip[] = {0,0,0,0};                        // left blank for DHCP
  static byte dnsip[] = {0,0,0,0};                       // left blank for DHCP
#else
  static byte myip[] = {192,168,1,202};                  // modify these addresses to match
  static byte gwip[] = {192,168,1,1};                    // your local network scheme.
#endif

#define LED 6                                            // blinky light define

long last_ms = 0;                                        // how long it too last time through

byte Ethernet::buffer[512];                              // tcp/ip buffer

static long timer_update;                                // holds the interval timer for serial printing
static long timer_post;                                  // holds the interval timer for internet posting

float tempC;                                             // read Celsius temperature is held here
float tempF;                                             // calculated Farenheit temp is held here

LibTemperature temp = LibTemperature(0);                 // instantiate a temp sensor


//*****************
//*** FUNCTIONS ***
//**********************************************
//*** call NanodeMAC to read the MAC address ***
//**********************************************
#ifdef NANODE
  NanodeMAC mac(mymac);                                  // read the MAC chip if a Nanode5
#endif

//**************************************************
//*** called when the client request is complete ***
//**************************************************
static void my_result_cb (byte status, word off, word len) 
{
  last_ms = millis() - timer_post;                       // calculate how long it took
    Serial.print("<<< reply ");
    Serial.print(last_ms);
    Serial.println(" ms");
    #ifdef DEBUG
      Serial.println((const char*) Ethernet::buffer + off);
    #endif
}


void setup () 
{
  pinMode(LED, OUTPUT);
  digitalWrite(LED, LOW);                                // Turn it ON (reverse logic)

  Serial.begin(9600);
  Serial.println("\n[WSAH_temp 0.1]");

  #ifdef DEBUG
    for( int i=0; i<6; i++ ) 
    {
      if (mymac[i]<0x10)
      {
        Serial.print("0");
      }
      Serial.print( mymac[i], HEX );
      Serial.print( i < 5 ? ":" : "" );
    }
    Serial.println("\nInit ENC28J60");
  #endif


  if (ether.begin(sizeof Ethernet::buffer, mymac) == 0)
  {
     Serial.println( "Failed to access Ethernet controller");
     blinkforever(500);
  }
  
  #ifdef DHCP  
    if (!ether.dhcpSetup())
    {
      Serial.println("DHCP failed");
      blinkforever(100);
    }
  #else
    ether.staticSetup(myip, gwip);
    ether.copyIp(ether.hisip, hisip);
  #endif

  if (!ether.dnsLookup(HOSTNAME))
  {
    Serial.println("DNS failed");
    blinkforever(250);
  }
  
  ether.printIp("IP Addr: ", ether.myip);
  ether.printIp("GW IP: ", ether.gwip);
  ether.printIp("DNS IP: ", ether.dnsip);
  ether.printIp("Server: ", ether.hisip);
  
  while (ether.clientWaitingGw())
    ether.packetLoop(ether.packetReceive());
  Serial.println("Gateway found");

  timer_update = - UPDATE_RATE;                          // start timing out right away
  timer_post = - POST_RATE;
  
  digitalWrite(LED, HIGH);                               // Turn it OFF (reverse logic)
  
  for(int x=0; x<=5; x++)
  {
    Serial.println("hitting page");
    ether.browseUrl(PSTR("/php_db/wsah_temp.php"), "", HOSTNAME, my_result_cb);
  }



}


void loop()
{
  unsigned long currentMillis = millis();                // take note of what time it is
  


  #ifdef DHCP
    if (ether.dhcpExpired() && !ether.dhcpSetup())       // DHCP expiration is a bit brutal, 
    {                                                    // because all other ethernet activity and
      Serial.println("DHCP failed");                     // incoming packets will be ignored
      blinkforever(100);                                 // until a new lease has been acquired
    }
  #endif

  ether.packetLoop(ether.packetReceive());               // go see if anything is coming in the network
  
  tempC = temp.GetTemperature();                         // go read the temperature in Degrees C
  tempF = (tempC * 9 / 5) + 32;                          // declare and convert the temperature into Degrees F

  if(millis() > timer_post + POST_RATE)                  // is it time to print a result?
  {
    timer_post = millis();                               // reset the timer
    sendDataToWebserver();                               // and go send the data to the webserver
  }

  if(millis() > timer_update + UPDATE_RATE)
  {
    timer_update = millis();
    Serial.print("Temp: ");
    Serial.print(tempF);
    Serial.print("F  ");
    Serial.print(tempC);
    Serial.println("C");
  }
}



void sendDataToWebserver()
{
  digitalWrite(LED, LOW);                                // Turn it ON (reverse logic)

  char vstr_tempC[8];
  char vstr_tempF[8];
  
  Serial.println("\n>>> sending packet...");

  // construct the PHP string into paramString using sprintf
  char paramString[128];
  sprintf(paramString, "?db=%s&table=%s&tempC=%s&tempF=%s&millis=%i", DATABASE, TABLE, ftoa(vstr_tempC, tempC, 2), ftoa(vstr_tempF, tempF, 2), last_ms);
  Serial.println(paramString);

  ether.browseUrl(PSTR("/php_db/wsah_temp.php"), paramString, HOSTNAME, my_result_cb);
  
  digitalWrite(LED, HIGH);                                // Turn it OFF (reverse logic)
}

//*******************************************************
//*** Convert float to string, in the style of itoa() ***
//*******************************************************
char *ftoa(char *a, double f, int precision)
{
  long p[] = {0,10,100,1000,10000,100000,1000000,10000000,100000000};
  
  char *ret = a;
  long heiltal = (long)f;
  itoa(heiltal, a, 10);
  while (*a != '\0') a++;
  *a++ = '.';
  long desimal = abs((long)((f - heiltal) * p[precision]));
  itoa(desimal, a, 10);
  return ret;
}

void blinkforever(int rate)
{
  while(1)
  {
    delay(rate);
    digitalWrite(LED, HIGH);
    delay(rate);
    digitalWrite(LED, LOW);
  }
}
