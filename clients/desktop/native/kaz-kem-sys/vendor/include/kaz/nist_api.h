/*
NIST-developed software is provided by NIST as a public service. You may use, copy, and distribute copies of the software in any medium, provided that you keep intact this entire notice. You may improve, modify, and create derivative works of the software or any portion of the software, and you may copy and distribute such modifications or works. Modified works should carry a notice stating that you changed the software and should note the date and nature of any such change. Please explicitly acknowledge the National Institute of Standards and Technology as the source of the software.

NIST-developed software is expressly provided "AS IS." NIST MAKES NO WARRANTY OF ANY KIND, EXPRESS, IMPLIED, IN FACT, OR ARISING BY OPERATION OF LAW, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTY OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, NON-INFRINGEMENT, AND DATA ACCURACY. NIST NEITHER REPRESENTS NOR WARRANTS THAT THE OPERATION OF THE SOFTWARE WILL BE UNINTERRUPTED OR ERROR-FREE, OR THAT ANY DEFECTS WILL BE CORRECTED. NIST DOES NOT WARRANT OR MAKE ANY REPRESENTATIONS REGARDING THE USE OF THE SOFTWARE OR THE RESULTS THEREOF, INCLUDING BUT NOT LIMITED TO THE CORRECTNESS, ACCURACY, RELIABILITY, OR USEFULNESS OF THE SOFTWARE.

You are solely responsible for determining the appropriateness of using and distributing the software and you assume all risks associated with its use, including but not limited to the risks and costs of program errors, compliance with applicable laws, damage to or loss of data, programs or equipment, and the unavailability or interruption of operation. This software is not intended to be used in any situation where a failure could cause risk of injury or damage to property. The software developed by NIST employees is not subject to copyright protection within the United States.
*/

//   This is a sample 'api.h' for use 'kem.c'

#ifndef api_h
#define api_h

#include "kem.h"

/* Algorithm name depends on security level */
#ifdef KAZ_SECURITY_LEVEL
    #if KAZ_SECURITY_LEVEL == 128
        #define CRYPTO_ALGNAME "KAZ-KEM-128"
    #elif KAZ_SECURITY_LEVEL == 192
        #define CRYPTO_ALGNAME "KAZ-KEM-192"
    #elif KAZ_SECURITY_LEVEL == 256
        #define CRYPTO_ALGNAME "KAZ-KEM-256"
    #else
        #define CRYPTO_ALGNAME "KAZ-KEM"
    #endif
#else
    /* Runtime level selection - algorithm name determined at runtime */
    #define CRYPTO_ALGNAME "KAZ-KEM"
#endif

/* NIST KEM API Functions */
int
crypto_kem_keypair(unsigned char *pk, unsigned char *sk);

int
crypto_encap(unsigned char *encapsulate, unsigned long long *encaplen,
             const unsigned char *m, unsigned long long mlen,
             const unsigned char *pk);

int
crypto_decap(unsigned char *decapsulate, unsigned long long *decaplen,
             const unsigned char *encap, unsigned long long encaplen,
             const unsigned char *sk);

/* Runtime initialization (use this instead of compile-time level) */
int crypto_kem_init(int security_level);

/* Get algorithm name for current security level */
const char* crypto_kem_algname(void);

#endif /* api_h */
