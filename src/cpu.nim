import random

const ROMSIZE: int = 0xFFF

type
  Chip8CPU* = ref object
    screenData*: array[320, array[640, array[3, byte]]]
    gameMemory: array[ROMSIZE, byte]
    registers: array[16, byte]
    addressI: uint16
    programCounter: uint16
    stack: seq[uint16]
    keyState: array[16, byte]
    delayTimer: byte
    soundTimer: byte

template nnn(opcode: uint16): uint16 =
  opcode and 0x0FFF

template nn(opcode: uint16): byte =
  byte(opcode and 0x00FF)

template regx(opcode: uint16): int =
  int(opcode and 0x0F00) shr 8

template regy(opcode: uint16): int =
  int(opcode and 0x00F0) shr 4

proc clear[T](arr: var openArray[T]) =
  for i in 0 .. arr.high:
    arr[i] = 0

proc reset(cpu: var Chip8CPU) =
  cpu.addressI = 0
  cpu.programCounter = 0x200
  cpu.registers.clear()
  cpu.gameMemory.clear()
  cpu.keyState.clear()
  cpu.delayTimer = 0
  cpu.soundTimer = 0

proc clearScreen(cpu: var Chip8CPU) =
  for x in 0 ..< 640:
    for y in 0 ..< 320:
      cpu.screenData[y][x][0] = 255
      cpu.screenData[y][x][1] = 255
      cpu.screenData[y][x][2] = 255

proc getKeyPressed(cpu: var Chip8CPU): int =
  var res: int = -1
  for i in 0 ..< 16:
    if cpu.keyState[i] > 0'u8:
      return i
  return res

#opcodes
#return from subroutine
proc opcode00EE(cpu: var Chip8CPU) =
  cpu.programCounter = cpu.stack[cpu.stack.high]
  discard cpu.stack.pop()

#jump to address NNN
proc opcode1NNN(cpu: var Chip8CPU, opcode: uint16) =
  cpu.programCounter = opcode.nnn

#call subroutine NNN
proc opcode2NNN(cpu: var Chip8CPU, opcode: uint16) =
  cpu.stack.add(cpu.programCounter)
  cpu.programCounter = opcode.nnn

#skip next instruction if VX == NN
proc opcode3XNN(cpu: var Chip8CPU, opcode: uint16) =
  if cpu.registers[opcode.regx] == opcode.nn:
    cpu.programCounter += 2

#skip next instruction if VX != NN
proc opcode4XNN(cpu: var Chip8CPU, opcode: uint16) =
  if cpu.registers[opcode.regx] != opcode.nn:
    cpu.programCounter += 2

#skip next instruction if VX == VY
proc opcode5XY0(cpu: var Chip8CPU, opcode: uint16) =
  if cpu.registers[opcode.regx] == cpu.registers[opcode.regy]:
    cpu.programCounter += 2

#sets vx to nn
proc opcode6XNN(cpu: var Chip8CPU, opcode: uint16) =
  cpu.registers[opcode.regx] = opcode.nn

#adds nn to vx. carry not affected
proc opcode7XNN(cpu: var Chip8CPU, opcode: uint16) =
  cpu.registers[opcode.regx] += opcode.nn

#sets vx to vy
proc opcode8XY0(cpu: var Chip8CPU, opcode: uint16) =
  cpu.registers[opcode.regx] = cpu.registers[opcode.regy]

#vx = vx | vy
proc opcode8XY1(cpu: var Chip8CPU, opcode: uint16) =
  var
    ivx = opcode.regx
    ivy = opcode.regy
  cpu.registers[ivx] = cpu.registers[ivx] or cpu.registers[ivy]

#vx = vx & vy
proc opcode8XY2(cpu: var Chip8CPU, opcode: uint16) =
  let
    ivx = opcode.regx
    ivy = opcode.regy
  cpu.registers[ivx] = cpu.registers[ivx] and cpu.registers[ivy]

#vx = vx xor vy
proc opcode8XY3(cpu: var Chip8CPU, opcode: uint16) =
  let
    ivx = opcode.regx
    ivy = opcode.regy
  cpu.registers[ivx] = cpu.registers[ivx] xor cpu.registers[ivy]

#add vy to vx. set carry to 1 if overflow
proc opcode8XY4(cpu: var Chip8CPU, opcode: uint16) =
  cpu.registers[0xF] = 0
  let
    ivx = opcode.regx
    ivy = opcode.regy
  if (int(cpu.registers[ivx]) +
      int(cpu.registers[ivy])) > 255:
    cpu.registers[0xF] = 1
  cpu.registers[ivx] = cpu.registers[ivx] + cpu.registers[ivy]

#sub vy from vx. set carry to 1 if no borrow
proc opcode8XY5(cpu: var Chip8CPU, opcode: uint16) =
  cpu.registers[0xF] = 1
  let
    ivx = opcode.regx
    ivy = opcode.regy

  if cpu.registers[ivx] < cpu.registers[ivy]:
    cpu.registers[0xF] = 0

  cpu.registers[ivx] = cpu.registers[ivx] - cpu.registers[ivy]

#shifts vx right by one. vf is set to the value of the least significant bit of vx before the shift
proc opcode8XY6(cpu: var Chip8CPU, opcode: uint16) =
  let ivx = opcode.regx
  cpu.registers[0xF] = cpu.registers[ivx] and 0x1
  cpu.registers[ivx] = cpu.registers[ivx] shr 1

#sets vx to vy minus vx. vf is set to 0 when there's a borrow
proc opcode8XY7(cpu: var Chip8CPU, opcode: uint16) =
  cpu.registers[0xF] = 1
  let
    ivx = opcode.regx
    ivy = opcode.regy

  if cpu.registers[ivy] < cpu.registers[ivx]:
    cpu.registers[0xF] = 0

  cpu.registers[ivx] = cpu.registers[ivy] - cpu.registers[ivx]

#shifts vx left by one. vf is set to the value of the most significant bit of vx before the shift
proc opcode8XYE(cpu: var Chip8CPU, opcode: uint16) =
  let ivx = opcode.regx
  cpu.registers[0xF] = cpu.registers[ivx] shr 7
  cpu.registers[ivx] = cpu.registers[ivx] shl 1

#skip next instruction if vx != vy
proc opcode9XY0(cpu: var Chip8CPU, opcode: uint16) =
  if cpu.registers[opcode.regx] != cpu.registers[opcode.regy]:
    cpu.programCounter += 2

#set I to NNN
proc opcodeANNN(cpu: var Chip8CPU, opcode: uint16) =
  cpu.addressI = opcode.nnn

#jump to address NNN + V0
proc opcodeBNNN(cpu: var Chip8CPU, opcode: uint16) =
  cpu.programCounter = uint16(cpu.registers[0]) + opcode.nnn

#set vx to rand + NN
proc opcodeCXNN(cpu: var Chip8CPU, opcode: uint16) =
  cpu.registers[opcode.regx] = byte(rand(255)) and opcode.nn

#draw sprite at (vx, vy) with width 8px and height Npx
#vf set to 1 if any screen pixels are flipped
proc opcodeDXYN(cpu: var Chip8CPU, opcode: uint16) =
  const SCALE: int = 10
  let
    coordx = int(cpu.registers[opcode.regx]) * SCALE
    coordy = int(cpu.registers[opcode.regy]) * SCALE
    height = uint32(opcode) and 0x000F

  cpu.registers[0xF] = 0

  for yline in 0'u32 ..< height:
    let data = cpu.gameMemory[uint32(cpu.addressI) + yline]
    var xpixelinv = 7
    for xpixel in 0 ..< 8:
      let mask = byte(1 shl xpixelinv)
      if (data and mask) != 0'u8:
        let
          x = xpixel * SCALE + coordx
          y = coordy + int(yline) * SCALE
        var color: byte = 0
        if cpu.screenData[y][x][0] == 0:
          color = 255
          cpu.registers[0xF] = 1
        for i in 0 ..< SCALE:
          for j in 0 ..< SCALE:
            cpu.screenData[y + i][x + j][0] = color
            cpu.screenData[y + i][x + j][1] = color
            cpu.screenData[y + i][x + j][2] = color
      dec xpixelinv

#skip the next instruction if they key stored in vx is pressed
proc opcodeEX9E(cpu: var Chip8CPU, opcode: uint16) =
  let key = cpu.registers[opcode.regx]
  if cpu.keyState[key] == 1:
    cpu.programCounter += 2

#skip the next instruction if the key stored in VX isn't pressed
proc opcodeEXA1(cpu: var Chip8CPU, opcode: uint16) =
  let key = cpu.registers[opcode.regx]
  if cpu.keyState[key] == 0:
    cpu.programCounter += 2

#sets vx to the value of the delay timer
proc opcodeFX07(cpu: var Chip8CPU, opcode: uint16) =
  cpu.registers[opcode.regx] = cpu.delayTimer

#a keypress is awaited and then stored in vx
proc opcodeFX0A(cpu: var Chip8CPU, opcode: uint16) =
  let keypressed = cpu.getKeyPressed()
  if keypressed == -1:
    cpu.programCounter -= 2
  else:
    cpu.registers[opcode.regx] = byte(keypressed)

#delay to vx
proc opcodeFX15(cpu: var Chip8CPU, opcode: uint16) =
  cpu.delayTimer = cpu.registers[opcode.regx]

#sound to vx
proc opcodeFX18(cpu: var Chip8CPU, opcode: uint16) =
  cpu.soundTimer = cpu.registers[opcode.regx]

#adds vx to I
proc opcodeFX1E(cpu: var Chip8CPU, opcode: uint16) =
  cpu.addressI += cpu.registers[opcode.regx]

#set i to the location of the sprite for the character in VX. Char 0-F are represented by 4x5 font
proc opcodeFX29(cpu: var Chip8CPU, opcode: uint16) =
  cpu.addressI = cpu.registers[opcode.regx] * 5

#stores the binary-coded decimal repr of vx at the address I, I + 1, I + 2
proc opcodeFX33(cpu: var Chip8CPU, opcode: uint16) =
  let value = cpu.registers[opcode.regx]
  cpu.gameMemory[cpu.addressI] = value div 100
  cpu.gameMemory[cpu.addressI+1] = (value div 10) mod 10
  cpu.gameMemory[cpu.addressI+2] = value mod 10

#stores V0 to VX in memory starting at addr i
proc opcodeFX55(cpu: var Chip8CPU, opcode: uint16) =
  let
    ivx = opcode.regx
    iaddr = int(cpu.addressI)
  for i in 0 .. ivx:
    cpu.gameMemory[iaddr+i] = cpu.registers[i]
  cpu.addressI = cpu.addressI + uint16(ivx) + 1

#fills v0 to vx with values from memory starting at address i
proc opcodeFX65(cpu: var Chip8CPU, opcode: uint16) =
  let
    ivx = opcode.regx
    iaddr = int(cpu.addressI)
  for i in 0 .. ivx:
    cpu.registers[i] = cpu.gameMemory[iaddr+i]
  cpu.addressI = cpu.addressI + uint16(ivx) + 1

proc getNextOpcode(cpu: var Chip8CPU): uint16 =
  result = uint16(cpu.gameMemory[cpu.programCounter]) shl 8
  result = result or uint16(cpu.gameMemory[cpu.programCounter+1])
  cpu.programCounter += 2

proc decodeOpcode8(cpu: var Chip8CPU, opcode: uint16) =
  case opcode and 0xF:
    of 0x0:
      cpu.opcode8XY0(opcode)
    of 0x1:
      cpu.opcode8XY1(opcode)
    of 0x2:
      cpu.opcode8XY2(opcode)
    of 0x3:
      cpu.opcode8XY3(opcode)
    of 0x4:
      cpu.opcode8XY4(opcode)
    of 0x5:
      cpu.opcode8XY5(opcode)
    of 0x6:
      cpu.opcode8XY6(opcode)
    of 0x7:
      cpu.opcode8XY7(opcode)
    of 0xE:
      cpu.opcode8XYE(opcode)
    else:
      discard

proc decodeOpcode0(cpu: var Chip8CPU, opcode: uint16) =
  case opcode and 0xF:
    of 0x0:
      cpu.clearScreen()
    of 0xE:
      cpu.opcode00EE()
    else:
      discard

proc decodeOpcodeE(cpu: var Chip8CPU, opcode: uint16) =
  case opcode and 0xF:
    of 0xE:
      cpu.opcodeEX9E(opcode)
    of 0x1:
      cpu.opcodeEXA1(opcode)
    else:
      discard

proc decodeOpcodeF(cpu: var Chip8CPU, opcode: uint16) =
  case opcode and 0xFF:
    of 0x07:
      cpu.opcodeFX07(opcode)
    of 0x0A:
      cpu.opcodeFX0A(opcode)
    of 0x15:
      cpu.opcodeFX15(opcode)
    of 0x18:
      cpu.opcodeFX18(opcode)
    of 0x1E:
      cpu.opcodeFX1E(opcode)
    of 0x29:
      cpu.opcodeFX29(opcode)
    of 0x33:
      cpu.opcodeFX33(opcode)
    of 0x55:
      cpu.opcodeFX55(opcode)
    of 0x65:
      cpu.opcodeFX65(opcode)
    else:
      discard

proc createCPU*(): Chip8CPU =
  result = new(Chip8CPU)
  result.stack = @[]

proc loadRom*(cpu: var Chip8CPU, romname: string): bool =
  cpu.reset()
  cpu.clearScreen()

  var f: File
  var fileOpened = f.open(romname)
  if not fileOpened:
    return false

  discard f.readBytes(cpu.gameMemory, 0x200, f.getFileSize())
  f.close()

  return true

proc keyPressed*(cpu: var Chip8CPU, key: int) =
  cpu.keyState[key] = 1

proc keyReleased*(cpu: var Chip8CPU, key: int) =
  cpu.keyState[key] = 0

proc decreaseTimers*(cpu: var Chip8CPU) =
  if cpu.delayTimer > 0'u8:
    dec cpu.delayTimer
  if cpu.soundTimer > 0'u8:
    dec cpu.soundTimer

proc executeNextOpcode*(cpu: var Chip8CPU) =
  let opcode = cpu.getNextOpcode()
  case opcode and 0xF000:
    of 0x0000:
      cpu.decodeOpcode0(opcode)
    of 0x1000:
      cpu.opcode1NNN(opcode)
    of 0x2000:
      cpu.opcode2NNN(opcode)
    of 0x3000:
      cpu.opcode3XNN(opcode)
    of 0x4000:
      cpu.opcode4XNN(opcode)
    of 0x5000:
      cpu.opcode5XY0(opcode)
    of 0x6000:
      cpu.opcode6XNN(opcode)
    of 0x7000:
      cpu.opcode7XNN(opcode)
    of 0x8000:
      cpu.decodeOpcode8(opcode)
    of 0x9000:
      cpu.opcode9XY0(opcode)
    of 0xA000:
      cpu.opcodeANNN(opcode)
    of 0xB000:
      cpu.opcodeBNNN(opcode)
    of 0xC000:
      cpu.opcodeCXNN(opcode)
    of 0xD000:
      cpu.opcodeDXYN(opcode)
    of 0xE000:
      cpu.decodeOpcodeE(opcode)
    of 0xF000:
      cpu.decodeOpcodeF(opcode)
    else:
      discard