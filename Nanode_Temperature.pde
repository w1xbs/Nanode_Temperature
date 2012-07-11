// Nanode graphing and logging
// July 2, 2012
//
// 07/06/12  working, would not DHCP on Comcast router (surprising-not!)
// 07/07/12  First commit to git
//
//
// Pachube bits from...
// Simple demo for feeding some random data to Pachube.
// 2011-07-08 <jc@wippler.nl> http://opensource.org/licenses/mit-license.php
//
// Twitter client parts uses supertweet.net as an OAuth authentication proxy. 
// Step by step instructions:
// 
//  1. Create an account on www.supertweet.net by logging with your twitter
//     credentials.
//  2. You'll be redirected to twitter to allow supertweet to post for you
//     on twitter.
//  3. Back on supertweet, set a password (different than your twitter one) and
//     activate your account clicking on "Make Active" link in from the table.
//  4. Wait for supertweet email to confirm your email address - won't work
//     otherwise.
//  5. Encode "un:pw" in base64: "un" being your twitter username and "pw" the
//     password you just set for supertweet.net. You can use this tool:
//        http://tuxgraphics.org/~guido/javascript/base64-javascript.html
//  6. Paste the result as the KEY string in the code bellow.
//
// Contributed by Inouk Bourgon <contact@inouk.imap.cc>
//     http://opensource.org/licenses/mit-license.php

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
#define TIME_OUT 30000                                   // time to wait for a response from internet (30 seconds)
float setpoint = 70.00;                                  // default setpoint upon first use
float differential = 2.50;                               // differential
char HOSTNAME[] PROGMEM = "ka1kjz.com";                  // hostname of a shared hosting server here
static byte hisip[] = {173,203,204,206};                 // ipaddress of the server here  
#define HTTPPATH "/php_db/nanode_temperature.php"        // path to the PHP script
#define DATABASE "nanode_temperature"                    // database name
#define TABLE "node1"                                    // table name
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
  static byte myip[] = {192,168,2,202};                  // modify these addresses to match
  static byte gwip[] = {192,168,2,1};                    // your local network scheme.
#endif

#define LED 6                                            // blinky light define

long last_ms = 0;                                        // how long it too last time through

byte Ethernet::buffer[512];                              // tcp/ip buffer

int brk;

static long timer_update;                                // holds the interval timer for serial printing
static long timer_post;                                  // holds the interval timer for internet posting

float tempC;                                             // read Celsius temperature is held here
float tempF;                                             // calculated Farenheit temp is held here

Stash stash;

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

    last_ms = millis() - timer_post;                     // calculate how long it took
    Serial.print("<<< reply ");
    Serial.print(last_ms);
    Serial.println(" ms");
    #ifdef DEBUG
      Serial.println((const char*) Ethernet::buffer + off);
    #endif
    brk = 1;
}


void setup ()                                            // this function executes only once (NOOB!)
{
  pinMode(LED, OUTPUT);                                  // setup the port for the LED
  digitalWrite(LED, LOW);                                // Turn it ON (reverse logic)

  Serial.begin(9600);                                    // setup the serial port
  Serial.println("\n[WSAH_temp 0.1]");                   // shoot out the name and version

  #ifdef DEBUG                                           // if debug is turned on...
    for( int i=0; i<6; i++ )                             // count to 6
    {
      if (mymac[i]<0x10)                                 // if mymac[i] has no leading 1, tack a 0 on it
      {
        Serial.print("0");                               // shoot a 0 out the serial port
      }
      Serial.print( mymac[i], HEX );                     // shoot the subject MAC digit out the serial port
      Serial.print( i < 5 ? ":" : "" );                  // if we printed 5 or less, put a colon in the mix
    }
    Serial.println("\nInit ENC28J60");                   // report that we are initializing the ethernet chip
  #endif


  if (ether.begin(sizeof Ethernet::buffer, mymac) == 0)  // set up ethernet stack with our buffer and MAC address
  {
     Serial.println( "Failed to access Ethernet controller"); // but if it returns anything but 0, we messed up
     blinkforever(500);                                  // and go into the blink routine forever
  }
  
  #ifdef DHCP  
    if (!ether.dhcpSetup())                              // setup DHCP and request addresses
    {
      Serial.println("DHCP failed");                     // but if it returns non 0, we messed up
      blinkforever(100);                                 // and go into the blink routine forever
    }
  #else
    ether.staticSetup(myip, gwip);                       // if not defined, set ip and gw with our own static values
    ether.copyIp(ether.hisip, hisip);                    // and inform the ethercard of our target mysql server
  #endif

  if (!ether.dnsLookup(HOSTNAME))                        // DNS the hostname as a test
  {
    Serial.println("DNS failed");                        // but if it returns non 0, we messed up
    blinkforever(250);                                   // and go into the blink routine forever
  }
  
  ether.printIp("IP Addr: ", ether.myip);                // print the IP addy out the serial port
  ether.printIp("GW IP: ", ether.gwip);                  // print the gateway addy out the serial port
  ether.printIp("DNS IP: ", ether.dnsip);                // print the DNS server addy out the serial port
  ether.printIp("Server: ", ether.hisip);                // print the target mysql server out the serial port
  
  while (ether.clientWaitingGw())                        // wait for a gateway packet to go by to ensure ARP happened
    ether.packetLoop(ether.packetReceive());

  Serial.println("Gateway found");                       // let us know configration is done

  timer_update = - UPDATE_RATE;                          // start timing out right away
  timer_post = - POST_RATE;                              // ditto
  
  digitalWrite(LED, HIGH);                               // Turn OFF the LED (reverse logic)
}


void loop()
{
  unsigned long currentMillis = millis();                // take note of what time it is
  
  #ifdef DHCP
    if (ether.dhcpExpired() && !ether.dhcpSetup())       // DHCP expiration is a bit brutal, 
    {                                                    // because all other ethernet activity and
      #ifdef DEBUG
        Serial.println("DHCP failed");                   // incoming packets will be ignored
      #endif
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
    while(1)
    {
      ether.packetLoop(ether.packetReceive());           // go see if anything is coming in the network
      if(brk)                                            // has the break flag been set?
      {
        brk = 0;                                         // reset break flag
        break;                                           // break the while loop;
      }
      else
      {
        if(millis() > timer_post + TIME_OUT)             // if we time out, break the while anyway
        {
          break;
        }
      }
    }
  }

  if(millis() > timer_update + UPDATE_RATE)
  {
    timer_update = millis();
    
    #ifdef DEBUG
      Serial.print("Temp: ");
      Serial.print(tempF);
      Serial.print("F  ");
      Serial.print(tempC);
      Serial.println("C");
    #endif
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

  ether.browseUrl(PSTR("/php_db/nanode_temperature.php"), paramString, HOSTNAME, my_result_cb);
  
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
