// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)
//(uchar)( val ^ 0xFF ) USEFUL!

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width

typedef unsigned char uchar;      //using uchar as shorthand

port p_scl = XS1_PORT_1E;         //interface ports to orientation
port p_sda = XS1_PORT_1F;

on tile[0] : in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
on tile[0] : out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6
int deadOrAlive(int value, int values[8]);

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////

void buttonListener(in port b, chanend toDist) {
  int r;
  while (1) {
    b when pinseq(15)  :> r;    // check that no button is pressed
    b when pinsneq(15) :> r;    // check if some buttons are pressed
    if ((r==13) || (r==14))     // if either button is pressed
    toDist <: r;             // send button pattern to userAnt
  }
}

int showLEDs(out port p, chanend fromVisualiser) {
  int pattern; //1st bit...separate green LED
               //2nd bit...blue LED
               //3rd bit...green LED
               //4th bit...red LED
  while (1) {
    fromVisualiser :> pattern;   //receive new pattern from visualiser
    p <: pattern;                //send pattern to LED port
  }
  return 0;
}

void DataInStream(char infname[], chanend c_out)
{
  int res; //resolution
  uchar line[ IMWD ]; //unsigned char array image width 16
  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT ); //Opens file and
  if( res ) {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }


  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ ) {
    _readinline( line, IMWD );

    for( int x = 0; x < IMWD; x++ ) {
      c_out <: line[ x ];
      printf( "-%4.1d ", line[ x ] ); //show image values
    }
    printf( "\n" );
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Start your implementation by changing this function to implement the game of life
// by farming out parts of the image to worker threads who implement it...
// Currently the function just inverts the image
//
/////////////////////////////////////////////////////////////////////////////////////////


void distributor(chanend datastream_in, chanend datastream_out, chanend fromAcc, chanend fromButtons)
{
  uchar val;
  int world[IMWD][IMHT];//array to store whole game
  int worldTemp[IMWD][IMHT];
  int running = 1;
  int buttonPress;
  int round = 1;
  int value;


  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size =h %dx%d\n", IMHT, IMWD );
  printf("Waiting for button press...\n");
  fromButtons :> buttonPress;
  if(buttonPress == 14){

      while(running){
          printf( "Waiting for Board Tilt...\n" );

          fromAcc :> value;
          while(value == 0){
                  fromAcc :> value;
          }

          printf( "Processing...\n" );
          if(round == 1){
              for( int y = 0; y < IMHT; y++ ) {   //go through all lines
                  for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
                      datastream_in :> val; //read the pixel value
                      world[x][y] = val; //building the world
                  }
              }
          }

          for(int y = 0; y < IMHT; y++){
              for(int x = 0; x <IMWD; x++){
                  //Finds 8 values around val.
                  int values[8];
                  values[0] = world[x][(y+(IMHT-1))%IMHT];
                  values[1] = world[(x+(IMWD+1))%IMWD][(y+(IMHT-1))%IMHT];
                  values[2] = world[(x+(IMWD+1))%IMWD][y];
                  values[3] = world[(x+(IMWD+1))%IMWD][(y+(IMHT+1))%IMHT];
                  values[4] = world[x][(y+(IMHT+1))%IMHT];
                  values[5] = world[(x+(IMWD-1))%IMWD][(y+(IMHT+1))%IMHT];
                  values[6] = world[(x+(IMWD-1))%IMWD][y];
                  values[7] = world[(x+(IMWD-1))%IMWD][(y+(IMHT-1))%IMHT];
                  worldTemp[x][y] = deadOrAlive(world[x][y],values); //change
              }
          }

          // Print function
          for( int y = 0; y < IMHT; y++ ) {
              int line[IMWD];
              for( int x = 0; x < IMWD; x++ ) {
                  line[x] = worldTemp[x][y];
                  printf( "-%4.1d ", line[ x ] ); //show image values
              }
              printf( "\n" );
          }

          // Assinging new values to world
          for(int y = 0; y < IMHT; y++){
              for(int x = 0; x <IMWD; x++){
                  world[x][y] = worldTemp[x][y];
              }
          }
          select {
              case fromButtons :> buttonPress:
                  if(buttonPress == 13){
                      for(int y = 0; y < IMHT; y++){
                          for(int x = 0; x <IMWD; x++){
                              datastream_out <: (uchar)world[x][y];

                          }
                      }
                  }
              break;
              default:
                  break;
          }

          //fromButtons :> buttonPress;
            if(buttonPress == 13){
                printf("yay\n");
            }

          // To Dataout
          //datastream_out <: (uchar)deadOrAlive(world[x][y],values);

          printf( "\n%d processing round completed...\n", round);
          round++;
      }
  }

//   for( int y = 0; y < IMHT; y++ ) {   //go through all lines
//     for( int x = 0; x < IMWD; x++ ) { //go through each pixel per line
//      datastream_out <: (uchar)((world[x][y]) ^ 0xFF ); //send some modified pixel out
//    }}



}


int deadOrAlive(int value, int values[8])    {
    int count = 0;
    for(int x = 0; x <8; x++){
        if(values[x] == 255){
            count++;
        }
    }
    if(count < 2 || count >3){
        return 0;
    }
    else if(value == 0 && count == 3){
        return 255;
    }
    else{
        return value;
    }
}







/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(char outfname[], chanend c_in)
{
  int res;
  int running = 1;
  uchar line[ IMWD ];


  //Open PGM file
  while(running){
  printf( "DataOutStream: Start...\n" );
  res = _openoutpgm( outfname, IMWD, IMHT );
  if( res ) {
    printf( "DataOutStream: Error opening %s\n.", outfname );
    return;
  }

  //Compile each line of the image and write the image line-by-line
  for( int y = 0; y < IMHT; y++ ) {
    for( int x = 0; x < IMWD; x++ ) {
      c_in :> line[ x ];

    }
    _writeoutline( line, IMWD );
    printf( "DataOutStream: Line written...\n" );
   }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  }
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation, send first tilt event to channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist) {
  i2c_regop_res_t result;
  char status_data = 0;

  // Configure FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  // Enable FXOS8700EQ
  result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
  if (result != I2C_REGOP_SUCCESS) {
    printf("I2C write reg failed\n");
  }

  //Probe the orientation x-axis forever
  while (1) {

    //check until new orientation data is available
    do {
      status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
    } while (!status_data & 0x08);

    //get new x-axis tilt value
    int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

    //send signal to distributor after first tilt

    if (x>30) {
        toDist <: 1;
    }else{
        toDist <: 0;
    }
  }
 }


/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void) {

i2c_master_if i2c[1];               //interface to orientation

char infname[] = "test.pgm";     //put your input image path here
char outfname[] = "testout.pgm"; //put your output image path here
chan inStreamToD, outStreamToD, orientations, buttonsToD;    //extend your channel definitions here

par {
    i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    orientation(i2c[0], orientations);        //client thread reading orientation data
    DataInStream(infname, inStreamToD);         //thread to read in a PGM image
    DataOutStream(outfname, outStreamToD);       //thread to write out a PGM image
    distributor(inStreamToD, outStreamToD, orientations, buttonsToD);//thread to coordinate work on image
    buttonListener(buttons, buttonsToD);
  }

  return 0;
}
