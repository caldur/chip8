import tables, strutils
import sdl2, opengl
import cpu

const
  windowWidth = 640'i32
  windowHeight = 320'i32

proc logMessage(message: string) =
  echo message

proc renderFrame(cpu: Chip8CPU) =
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  glLoadIdentity()
  glRasterPos2i(-1, 1)
  glPixelZoom(1, -1)
  glDrawPixels(windowWidth, windowHeight, GL_RGB, GL_UNSIGNED_BYTE, cpu.screenData.unsafeAddr)

proc getKey(keycode: TScancode): int =
  case keycode:
    of SDL_SCANCODE_X: 0
    of SDL_SCANCODE_1: 1
    of SDL_SCANCODE_2: 2
    of SDL_SCANCODE_3: 3
    of SDL_SCANCODE_Q: 4
    of SDL_SCANCODE_W: 5
    of SDL_SCANCODE_E: 6
    of SDL_SCANCODE_A: 7
    of SDL_SCANCODE_S: 8
    of SDL_SCANCODE_D: 9
    of SDL_SCANCODE_Z: 10
    of SDL_SCANCODE_C: 11
    of SDL_SCANCODE_4: 12
    of SDL_SCANCODE_R: 13
    of SDL_SCANCODE_F: 14
    of SDL_SCANCODE_V: 15
    else: -1

proc handleInput(cpu: var Chip8CPU, evt: Event) =
  if evt.kind == KeyDown:
    var key = getKey(evt.key.keysym.scancode)
    if key != -1:
      cpu.keyPressed(key)
  elif evt.kind == KeyUp:
    var key = getKey(evt.key.keysym.scancode)
    if key != -1:
      cpu.keyReleased(key)

proc doEmulatorLoop(cpu: var Chip8CPU, settings: Table[string, string]) =
  if not settings.hasKey("OpcodesPerSecond"):
    logMessage("The OpcodesPerSecond setting cannot be found in game.ini")
    return

  let
    fps = 60
    numopcodes = settings["OpcodesPerSecond"].parseInt()
    numframe = numopcodes div fps
    interval = uint32(1000 div fps)

  var
    quit = false
    event = defaultEvent
    time2 = getTicks()

  while not quit:
    while pollEvent(event):
      cpu.handleInput(event)
      if event.kind == QuitEvent:
        quit = true

    var current = getTicks()

    if (time2 + interval) < current:
      cpu.decreaseTimers()
      for i in 0 ..< numframe:
        cpu.executeNextOpcode()