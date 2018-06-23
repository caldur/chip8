import tables, strutils
import sdl2, opengl
import cpu

const
  windowWidth = 640'i32
  windowHeight = 320'i32

var
  window: WindowPtr
  context: GlContextPtr

proc logMessage(message: string) =
  echo message

proc renderFrame(cpu: Chip8CPU) =
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  glLoadIdentity()
  glRasterPos2i(-1, 1)
  glPixelZoom(1, -1)
  glDrawPixels(windowWidth, windowHeight, GL_RGB, GL_UNSIGNED_BYTE, cpu.screenData.unsafeAddr)
  window.glSwapWindow()
  glFlush()

proc getKey(keycode: Scancode): int =
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
      time2 = current
      cpu.renderFrame()

proc loadGameSettings(settings: var Table[string, string]): bool =
  var content: string
  try:
    content = readFile("game.ini")
  except IOError:
    logMessage("could not open settings file game.ini")
    return false

  for line in content.splitLines():
    if line == "" or line[0] == '*':
      continue
    let kv = line.split(":")
    settings.add(kv[0], kv[1])

  return true

proc initGL() =
  glViewport(0, 0, windowWidth, windowHeight)
  glMatrixMode(GL_MODELVIEW)
  glLoadIdentity()
  glOrtho(0.0, windowWidth.toFloat(), windowHeight.toFloat(), 0, -1.0, 1.0)
  glClearColor(0, 0, 0, 1.0)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
  glShadeModel(GL_FLAT)

  glEnable(GL_TEXTURE_2D)
  glDisable(GL_DEPTH_TEST)
  glDisable(GL_CULL_FACE)
  glDisable(GL_DITHER)
  glDisable(GL_BLEND)

proc createSDLWindow() =
  discard sdl2.init(INIT_EVERYTHING)

  discard glSetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2)
  discard glSetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 1)
  discard glSetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_COMPATIBILITY)

  window = createWindow("Chip 8 Emu",
    SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
    windowWidth, windowHeight,
    SDL_WINDOW_SHOWN or SDL_WINDOW_OPENGL
    )

  context = window.glCreateContext()
  if context.isNil:
    echo "failed to create context"
  loadExtensions()
  discard glSetSwapInterval(1)
  initGL()

proc loadChip8Rom(cpu: var Chip8CPU, settings: Table[string, string]): bool =
  if not settings.hasKey("RomName"):
    logMessage("The RomName setting cannot be found in game.ini")
    return false
  cpu.loadRom(settings["RomName"])

when isMainModule:
  var
    settings = initTable[string, string]()
    emuCpu = createCPU()
    success: bool

  success = loadGameSettings(settings)
  if not success:
    logMessage("error loading settings from game.ini")
    quit(1)

  createSDLWindow()

  success = emuCpu.loadChip8Rom(settings)
  if not success:
    logMessage("Error loading chip8 rom")
    sdl2.quit()
    quit(1)

  emuCpu.doEmulatorLoop(settings)

  sdl2.quit()
  quit(0)