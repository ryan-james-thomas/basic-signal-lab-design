#include <ctype.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <unistd.h> //This header is needed for getopt()
#include "rp.h"     //This header is the Red Pitaya API

int main(int argc, char **argv) {

    char port;      //Port to write to
    char value;     //Value to write
    char flag = 0;  //Output (0) or input (1)

    int c;
    while ((c = getopt(argc,argv,"p:v:io")) != -1) {
        switch (c) {
            case 'p':
                port = atoi(optarg);
                break;
            case 'v':
                value = atoi(optarg);
                break;
            case 'i':
                flag = 1;
                break;
            case 'o':
                flag = 0;
                break;
            case '?':
                if (isprint (optopt))
                    fprintf (stderr, "Unknown option `-%c'.\n", optopt);
                else
                    fprintf (stderr,
                            "Unknown option character `\\x%x'.\n",
                            optopt);
                return 1;
            default:
                abort();
                break;
        }
    }

    switch (port) {
        case 1:
            port = RP_CH_1;
            break;
        case 2:
            port = RP_CH_2;
            break;
        default:
            fprintf(stderr,"Port must be either 1 or 2!\n");
            return 1;
    }
    
    switch (value) {
        case 0:
            if (flag) {
                value = RP_LOW;         //Low-voltage input setting
            } else {
                value = RP_GAIN_1X;     //Low gain output setting
            }
            break;
        case 1:
            if (flag) {
                value = RP_HIGH;        //High-voltage input setting
            } else {
                value = RP_GAIN_5X;     //High gain output setting
            }
            break;
        default:
            fprintf(stderr,"Gain setting must be either 0 (low) or 1 (high)!\n");
            return 1;
    }
    /*
     * The examples use rp_Init(), but this resets all systems to
     * their default values.  We just need to initialize the API
     * so we use InitReset(false) which does not reset things.
     * This should be safe to use with other FPGA images
     */
    if (rp_InitReset(false) != RP_OK) {
        fprintf(stderr,"RP API initialization failed!\n");
        return 1;
    }
    /*
     * Set output gain or input attentuation
     */
    if (flag) {
        rp_AcqSetGain(port,value);
        printf("Attenutation on input %d set to %d\n",port + 1,value);
    } else {
        rp_GenSetGainOut(port,value);
        printf("Gain on output %d set to %d\n",port + 1,value);
    }
    rp_Release();

    
    return 0;
}
