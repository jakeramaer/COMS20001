// COMS20001 - Cellular Automaton Farm - Initial Code Skeleton
// (using the XMOS i2c accelerometer demo code)
//(uchar)( val ^ 0xFF ) USEFUL!

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include <stdbool.h>
#include "pgmIO.h"
#include "i2c.h"

#define  IMHT 64                  //image height
#define  IMWD 64                  //image width

typedef unsigned char uchar;      //using uchar as shorthand

on tile[0]: port p_scl = XS1_PORT_1E;         //interface ports to orientation
on tile[0]: port p_sda = XS1_PORT_1F;

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
int deadOrAlive(int value, int values[8]); // Declaring functions


/////////////////////////////////////////////////////////////////////////////////////////
//
// Helper Functons
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

int showLEDs(out port p, chanend fromDist) {
  int pattern; //1st bit...separate green LED, 2nd bit...blue LED, 3rd bit...green LED, 4th bit...red LED
  while (1) {
      select  {
          case fromDist :> pattern:
              p <: pattern;
              break;
          default:
              break;
      }
  }
  return 0;
}

int deadOrAlive(int value, int values[8])    {  // This will have to be changed for bitpacking
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

void timerFunction(chanend fromDist) {
    timer t;
    unsigned int time;

    int go;
    int time1;
    const unsigned int period = 100000; // period of 1s
    t :> time; // get the initial timer value
    fromDist :> go;
    while(go == 0){
        fromDist <: go;
    }
    while (1) {
        select {
            case t when timerafter ( time ) :> void :
                time += (period) ;
                time1 += 1;
                break;
            case fromDist :> go:
                if(go == 0) {
                    printf("Time (ms): %d\n", time1);
                    time1 = 0;
                }
                break;
        }
    }
}

int bitPacker(int result, int x, int n){
    if(x == 255){
        result = result | (1 << n);
    }
    return result;
}

int unPacker(int x, int n){
    return ((x & (1<<n))/(1<<n))*255;
}

int arraySum(uchar array[(IMWD/8)*3]){
    uchar sum;
    for(int x = 0; x < (IMWD/8)*3; x++){
        sum = sum + array[x];
    }
    return sum;
}

int bitDead(uchar world[3][IMWD], int x, uchar bitval) {

    int values[8];  //Finds 8 values around val.

    values[0] = world[0][x];
    values[1] = world[0][(x+(IMWD+1))%IMWD];
    values[2] = world[1][(x+((IMWD)+1))%IMWD];
    values[3] = world[2][(x+(IMWD+1))%IMWD];
    values[4] = world[2][x];
    values[5] = world[2][(x+(IMWD-1))%IMWD];
    values[6] = world[1][(x+(IMWD-1))%IMWD];
    values[7] = world[0][(x+(IMWD-1))%IMWD];
    return deadOrAlive(bitval,values); //changes values, stores in bitVal
}

void worker(int z, chanend fromDist, chanend above, chanend below)   {

    uchar val;
    int exec;
    int round = 1;
    uchar world[(IMHT/8)+2][IMWD/8]; //half of the board + edge cases
    uchar worldtemp[(IMHT/8)+2][IMWD/8];

    while(1){


    //  Round one - ONLY INPUTS ONCE
    if(round == 1)   {
        fromDist :> exec;   // Wait until control signal is sent from Dist
        for( int y = 1; y < (IMHT/8)+1; y++ ){  // world with no edge cases
            for( int x = 0 ; x < IMWD/8; x++ ) {
                fromDist :> val;
                world[y][x] = val;
            }
        }
    }

    fromDist :> exec; // synchronise send EDGE CASES between workers

    // Sending edge cases to one another - EVEN SEND
    for(int x = 0; x < IMWD/8; x++){
        if(z%2 == 0){   //  if even
            above <: world[1][x];
            below <: world[(IMHT)/8][x];
        }
        else if(z%2 == 1){  //  if odd
            below :> world[(IMHT/8)+1][x];
            above :> world[0][x];
        }
    }
    // Sending edge cases to one another - ODD SEND
    for(int x = 0; x < IMWD/8; x++){
        if(z%2 == 1){
            above <: world[1][x];
            below <: world[(IMHT/8)][x];
        }
        else if(z%2 == 0){
            below :> world[(IMHT/8)+1][x];
            above :> world[0][x];
        }
    }

    // UNPACKING AND PROCESSING
    for(int y = 1; y <= (IMHT/8); y++){

            uchar values[(IMWD/8)*3];
            uchar bits[8];              //Temporary store for unpacked values
            uchar bitWorld[3][IMWD];    //Stores All unpacked values
            uchar bitWorldTemp[IMWD];   //Stores all new values from DeadOrAlive

            int counter = 0;
            for(int n = y-1; n <= y+1; n++)   { // Taking all values around x
                for(int x = 0; x <IMWD/8; x++){
                    values[counter] = world[n][x];
                    counter++;
                }
            }

            // adds every line to bitworld - UNPACKED
            for(int u = 0; u < 3; u++){
                for(int k = 0; k<IMWD/8; k++){
                      for(int i = 0; i<8; i++){
                              bitWorld[u][i+(k*8)] = unPacker(values[k + (u*(IMWD/8))],i); //Unpacks all bits and puts it into an array
                          }
                    }
                }

            // computes dead or alive - UNPACKED
            for(int a = 0; a < IMWD; a++){
                bitWorldTemp[a] = (uchar) bitDead(bitWorld, a , bitWorld[1][a]); //Generates new values for board and stores it temporarily in this array.

            }

            // Packing it back up
            for(int a = 0; a < IMWD/8; a++){
               int result = 0;
               for(int j = 0; j < 8; j++){
                   result = bitPacker(result, bitWorldTemp[j + (a*8)], j);
               }
               worldtemp[y][a] = result;
            }
    }

    // Assigning new values to world
    for(int y = 1; y <= (IMHT/8); y++){
        for(int x = 0; x <IMWD/8; x++){
            world[y][x] = worldtemp[y][x];
        }
    }

    // DATA OUT FUNCTION
    fromDist :> exec;
    if(exec == 2)    {
        for(int y = 1; y <= IMHT/8; y++){
            for(int x = 0; x<IMWD/8; x++){
                for(int i = 0; i<8; i++){
                    fromDist <: (uchar) unPacker(world[y][x],i); //Unpacks all bits and puts it into an array
                }
            }
        }
    }

    round++;
    }
}



/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataInStream(chanend c_out)
{
  char infname[] = "64x64.pgm";     //put your input image path here
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
      //printf( "-%4.1d ", line[ x ] ); //show image values
    }
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Distributer function
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend datastream_in, chanend datastream_out, chanend fromAcc, chanend fromButtons, chanend toLEDS, chanend toTimer, chanend toWorker[8])
{
  uchar val;
  int running = 1;
  int buttonPress;
  int round = 1;
  int value;

  //Starting up and wait for tilting of the xCore-200 Explorer
  printf( "ProcessImage: Start, size =h %dx%d\n", IMHT, IMWD );
  printf("Waiting for button press...\n");
  fromButtons :> buttonPress;

  if(buttonPress == 14){

      printf( "Waiting for Board Tilt...\n" );  //  Innitial board tilt
      while(running){

          fromAcc :> value;
          while(value == 1){
              fromAcc :> value;
          }

          if(round%100 == 0){
              toTimer <: 1; // Start timer
          }

          toLEDS <: 1; // To indicate processing


          // SEND VALUES
          if(round == 1){   // eventally this will be only bit of distributer to send values
              toLEDS <: 4;
              for(int i = 0; i < 8; i++){
                  toWorker[i] <: 1; // Sending exec values TO READ IN VALUES FROM DIST - only needed here
              }

              for(int z = 0; z < 8; z++){
              for( int y = 0; y < IMHT/8; y++ ) {   //go through all lines
                  for( int x = 0; x < IMWD/8; x++ ) { //go through each pixel per line
                          int result = 0;
                          for(int j = 0; j < 8; j++){
                              datastream_in :> val; //read the pixel value
                              result = bitPacker(result, val, j);
                          }
                          toWorker[z] <: (uchar) result; //building the world

                  }
              }
          }
              toLEDS <: 1;
          }
          for(int i = 0; i < 8; i++){
              toWorker[i] <: 1; // Sending exec values TO READ IN VALUES FROM DIST - only needed here
          }

          // DATA OUT FUNCION - SENDS 2 TO WORKERS IF DATA OUT, 1 IF NOT
          select {
              case fromButtons :> buttonPress:
                  if(buttonPress == 13){
                      toLEDS <: 2;
                      for(int z = 0; z <8; z++){
                      toWorker[z] <: 2;
                      for(int y = 0; y < IMHT/8; y++){
                          for(int x = 0; x <IMWD; x++){
                              toWorker[z] :> val;  //  recieving values from worker 0 and writing them out
                              datastream_out <: val;
                              }
                          }
                      }
                      }
                      toLEDS <: 0;
                  break;
              default:
                  for(int i = 0; i < 8; i++){
                      toWorker[i] <: 1; // Sending exec values TO READ IN VALUES FROM DIST - only needed here
                  }
                  break;
          }
          toLEDS <: 0; // To indicate finished processing
          if(round%100 == 0 && round != 0){
              toTimer <: 0;
          }else{
              toTimer <: 1;
          }
          //printf( "\n%d processing round completed...\n", round);
          round++;
      }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void DataOutStream(chanend c_in)
{
  char outfname[] = "testout.pgm"; //put your output image path here
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
      printf( "-%4.1d ", line[ x ]); // PRINTING FUNCTION - WILL BE REMOVED, ONLY TO SEE IF WORKS, IT FUCKING DOES
    }
    _writeoutline( line, IMWD );
    printf("\n");
    //printf( "DataOutStream: Line written...\n" );
   }

  //Close the PGM image
  _closeoutpgm();
  printf( "DataOutStream: Done...\n" );
  }
  return;
}


/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation constantly
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

i2c_master_if i2c[1];   //interface to orientation

chan inStreamToD, outStreamToD, orientations, buttonsToD, distToLEDS, distToTimer,workerConnect[8],distToWorker[8];     //extend your channel definitions here

par {
    on tile[0]: worker(0, distToWorker[0],workerConnect[0], workerConnect[1]);
    on tile[1]: worker(1, distToWorker[1],workerConnect[1], workerConnect[2]);
    on tile[0]: worker(2, distToWorker[2],workerConnect[2], workerConnect[3]);
    on tile[1]: worker(3, distToWorker[3],workerConnect[3], workerConnect[4]);
    on tile[0]: worker(4, distToWorker[4],workerConnect[4], workerConnect[5]);
    on tile[1]: worker(5, distToWorker[5],workerConnect[5], workerConnect[6]);
    on tile[0]: worker(6, distToWorker[6],workerConnect[6], workerConnect[7]);
    on tile[1]: worker(7, distToWorker[7],workerConnect[7], workerConnect[0]);
    on tile[0]: i2c_master(i2c, 1, p_scl, p_sda, 10);   //server thread providing orientation data
    on tile[0]: orientation(i2c[0], orientations);        //client thread reading orientation data
    on tile[1]: DataInStream(inStreamToD);         //thread to read in a PGM image
    on tile[1]: DataOutStream(outStreamToD);       //thread to write out a PGM image
    on tile[1]: distributor(inStreamToD, outStreamToD, orientations, buttonsToD, distToLEDS, distToTimer, distToWorker);//thread to coordinate work on image
    on tile[0]: buttonListener(buttons, buttonsToD);
    on tile[0]: showLEDs(leds, distToLEDS);
    on tile[1]: timerFunction(distToTimer);

  }

  return 0;
}
