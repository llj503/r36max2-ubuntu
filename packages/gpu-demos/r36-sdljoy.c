/* r36-sdljoy.c - print what SDL2/EmulationStation sees for each joystick: the name,
 * the GUID string ES keys its input configs on, and the button/axis/hat inventory.
 *
 * This exists so the joypad mapping can be pre-seeded from Batocera's controllers
 * database instead of running ES's first-boot configuration wizard, which needs
 * somebody to read the panel (and screenshots are blocked by weston's capture
 * authority).  No video subsystem is initialised, so it works from ssh.
 *
 * build: cc -O2 -Wall r36-sdljoy.c $(sdl2-config --cflags --libs)
 */
#include <SDL2/SDL.h>
#include <stdio.h>
#include <string.h>

static void guid_str(SDL_JoystickGUID g, char *out)
{
    /* SDL2's SDL_JoystickGUID is SDL_GUID { Uint8 data[16]; } - there is no .guid
       member (that was SDL1), which is what the first version of this file assumed */
    for (int i = 0; i < 16; i++)
        sprintf(out + i * 2, "%02x", (unsigned char)g.data[i]);
    out[32] = 0;
}

int main(void)
{
    if (SDL_Init(SDL_INIT_JOYSTICK) != 0) {
        printf("  SDL_Init(joystick) failed: %s\n", SDL_GetError());
        return 1;
    }
    int n = SDL_NumJoysticks();
    printf("  joysticks visible to SDL: %d\n", n);
    for (int i = 0; i < n; i++) {
        SDL_JoystickGUID g = SDL_JoystickGetDeviceGUID(i);
        char gs[33];
        guid_str(g, gs);
        printf("\n  [%d] guid=%s\n", i, gs);
        printf("      vendor=0x%04x product=0x%04x version=0x%04x\n",
               SDL_JoystickGetDeviceVendor(i), SDL_JoystickGetDeviceProduct(i),
               SDL_JoystickGetDeviceProductVersion(i));
        /* this header has no SDL_JoystickNameForDevice(); the name is available on
           the opened object, which is what we need anyway */
        SDL_Joystick *j = SDL_JoystickOpen(i);
        if (!j) { printf("      open failed: %s\n", SDL_GetError()); continue; }
        printf("      name=%s\n", SDL_JoystickName(j));
        printf("      buttons=%d axes=%d hats=%d balls=%d instance=%d\n",
               SDL_JoystickNumButtons(j), SDL_JoystickNumAxes(j), SDL_JoystickNumHats(j),
               SDL_JoystickNumBalls(j), SDL_JoystickInstanceID(j));
        /* SDL2 has no axis-range getters (that is SDL3's SDL_JoystickAxisGetMin);
           every SDL2 axis is a signed 16-bit -32768..32767, so ES treats them all
           the same and there is nothing per-axis to print here. */
        SDL_JoystickClose(j);
    }
    SDL_Quit();
    return 0;
}
