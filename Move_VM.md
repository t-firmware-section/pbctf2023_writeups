  
# Move VM Writeup
## Disassembling the bytecode
After some OSINT, we found out that "MOVE" is some kind of web3 smart contract language thing. We kept googling and we found its [toolchain]([https://github.com/move-language/move](https://github.com/move-language/move)). For some reason, couldn't build the docker successfully, so we ran `cargo build`, which built a few utils, but none of them was a disassembler. We looked a little further and saw that in order to get the disas, we need to change the Cargo.toml, we did that and finally got a **working** disassembler.
## Reversing the bytecode
After we finally got the disassembly, we start looking at what we have. First, we can see that all the code is inside a single function named "check_flag", and in the beginning we can find the CMPs with the constant "pbctf{", which means we're on the right track. If we look at the byte code, we can see many similar code blocks that repeat, and above each such code block a CMP between a local variable and a constant. Using the challenge's name, its plausible that the code implements a virtual machine, and that the CMP is the part that decodes the opcode. From the logic that decodes the instruction, we saw that the structure of the opcodes is as follows: 1. instruction is 8 bytes 2. First 4 bytes are the operand 3. Last 4 bytes (actually only a single byte from the 4) is the opcode. In the beginning we saw that the main loop iterates over an array of constants that are the VM bytecode:
```
B7: # Get next opcode
	94: CopyLoc[39](v_program: &vector<u64>)
	95: CopyLoc[45](v_pc: u64)
	96: VecImmBorrow(4)
	97: ReadRef
	98: StLoc[43](v_instruction: u64)
	99: CopyLoc[43](v_instruction: u64)
	100: LdU8(32)
	101: Shr
	102: LdU64(255)
	103: BitAnd
	104: CastU8
	105: StLoc[44](v_opcode: u8) # v_opcode = opcode?
	106: MoveLoc[43](v_instruction: u64)
	107: LdU64(4294967295) # 0xffffffff
	108: BitAnd
	109: CastU64
	110: StLoc[42](v_operand1: u64) # operand1
	111: CopyLoc[44](v_opcode: u8)
	112: LdU8(0)
	113: Eq
	114: BrFalse(119)
```
After a bit of trial and error, we found out that the first 2 bytes were a header.
Then, we proceeded to look at each opcode implementation which were all pretty easy to understand. For example, this is the bytecode that implements an ADD operation between the two topmost stack elements:
```
B17: # Fourth opcode
	158: CopyLoc[46](v_stack: &mut vector<u64>)
	159: VecPopBack(4)
	160: StLoc[9](loc8: u64)
	161: CopyLoc[46](v_stack: &mut vector<u64>)
	162: VecPopBack(4)
	163: StLoc[23](loc22: u64)
	164: CopyLoc[46](v_stack: &mut vector<u64>)
	165: MoveLoc[9](loc8: u64)
	166: CastU128
	167: MoveLoc[23](loc22: u64)
	168: CastU128
	169: Add
	170: LdU128(18446744073709551615) # 0xfffffffffffff
	171: BitAnd
	172: CastU64
	173: VecPushBack(4)
```
From here we wrote a simple disassembler.py:
```
PROGRAM = # Omitted for the sake of brevity

OPCODES = {
        0: ("PUSH", True),
        1: ("SIGN_EXTENDED_PUSH", True),
        2: ("GET_INPUT_BYTE", True), # Operand is index in input
        16: ("ADD", False),
        17: ("XOR", False),
        18: ("OR", False),
        19: ("AND", False),
        20: ("SHL", False), # SHL by byte from the stack
        21: ("SHR", False), # SHR by byte from the stack
        22: ("CMP_LESS_THAN", False), 
        23: ("CMP_EQUAL", False),
        48: ("DUPLICATE", False),
        49: ("PUSH_SECOND_ITEM_ON_STACK", False), #???
        50: ("PUSH_THIRD_ITEM_ON_STACK", False), #???
        51: ("PUSH_FOURTH_ITEM_ON_STACK", False), #???
        56: ("POP", False),
        57: ("SWAP", False),
        58: ("SWAP_SECOND_AND_THIRD", False),
        64: ("JMP_ABSOLUTE_IF_ZERO", True),
        65: ("JMP_RELATIVE_IF_ZERO", True),
        66: ("JMP_RELATIVE_BACK_IF_ZERO", True),
        67: ("RET", False),
        68: ("CALL", True),
        69: ("EXIT", False),
        70: ("NOP", False)
        }

def main():
    global PROGRAM

    INSTRUCTION_SIZE = 8
    ENDIANESS = "little"
    PROGRAM = PROGRAM[2:]

    output = ""
    for i in range(0, len(PROGRAM), INSTRUCTION_SIZE):
        instruction = PROGRAM[i:i+INSTRUCTION_SIZE]
        opcode = (int.from_bytes(instruction, ENDIANESS) >> 32) & 0xff #000000) >> 24
        operand = int.from_bytes(instruction, ENDIANESS) & 0xFFFFFFFF

        if not opcode in OPCODES:
            print("NO BUENO", hex(i // INSTRUCTION_SIZE), opcode, instruction.hex())
            continue
        if OPCODES[opcode][1]:
            output += f"{hex(i // INSTRUCTION_SIZE)}:\t{OPCODES[opcode][0]}\t{hex(operand)}\n"
        else:
            if operand != 0:
                print("NO BUENO 2", hex(operand), OPCODES[opcode])
            output += f"{hex(i // INSTRUCTION_SIZE)}:\t{OPCODES[opcode][0]}\n"

    with open("disas.txt", "w") as f:
        f.write(output)

if __name__ == "__main__":
    main()
```

Which then produced the following disassembly:
```
0x0:	PUSH	0x1
0x1:	JMP_ABSOLUTE_IF_ZERO	0x1e

0x2:	SWAP
0x3:	PUSH	0x0
0x4:	SWAP
0x5:	DUPLICATE
0x6:	PUSH	0x1
0x7:	SHR
0x8:	SWAP
0x9:	PUSH	0x1
0xa:	AND
0xb:	PUSH	0xffffffff
0xc:	XOR
0xd:	PUSH	0x1
0xe:	ADD
0xf:	PUSH	0xfff63b78
0x10:	AND
0x11:	XOR
0x12:	SWAP
0x13:	PUSH	0x1
0x14:	ADD
0x15:	DUPLICATE
0x16:	PUSH	0x8
0x17:	CMP_LESS_THAN
0x18:	SWAP_SECOND_AND_THIRD
0x1a:	SWAP
0x1b:	POP
0x1c:	SWAP
0x1d:	RET

0x1e:	PUSH	0x0
0x1f:	GET_INPUT_BYTE	0x6
0x20:	XOR
0x21:	CALL	0x2
0x22:	GET_INPUT_BYTE	0x7
0x23:	XOR
0x24:	CALL	0x2
0x25:	GET_INPUT_BYTE	0x8
0x26:	XOR
0x27:	CALL	0x2
0x28:	GET_INPUT_BYTE	0x9
0x29:	XOR
0x2a:	CALL	0x2
0x2b:	PUSH	0x83b118fa
0x2c:	CMP_EQUAL
0x2d:	JMP_RELATIVE_IF_ZERO	0x2
0x2f:	PUSH	0x0
0x30:	GET_INPUT_BYTE	0xa
0x31:	XOR
0x32:	CALL	0x2
0x33:	GET_INPUT_BYTE	0xb
0x34:	XOR
0x35:	CALL	0x2
0x36:	GET_INPUT_BYTE	0xc
0x37:	XOR
0x38:	CALL	0x2
0x39:	GET_INPUT_BYTE	0xd
0x3a:	XOR
0x3b:	CALL	0x2
0x3c:	PUSH	0xef9c7b7f
0x3d:	CMP_EQUAL
0x3e:	JMP_RELATIVE_IF_ZERO	0x2
0x40:	PUSH	0x0
0x41:	GET_INPUT_BYTE	0xe
0x42:	XOR
0x43:	CALL	0x2
0x44:	GET_INPUT_BYTE	0xf
0x45:	XOR
0x46:	CALL	0x2
0x47:	GET_INPUT_BYTE	0x10
0x48:	XOR
0x49:	CALL	0x2
0x4a:	GET_INPUT_BYTE	0x11
0x4b:	XOR
0x4c:	CALL	0x2
0x4d:	PUSH	0x95b3879f
0x4e:	CMP_EQUAL
0x4f:	JMP_RELATIVE_IF_ZERO	0x2
0x51:	PUSH	0x0
0x52:	GET_INPUT_BYTE	0x12
0x53:	XOR
0x54:	CALL	0x2
0x55:	GET_INPUT_BYTE	0x13
0x56:	XOR
0x57:	CALL	0x2
0x58:	GET_INPUT_BYTE	0x14
0x59:	XOR
0x5a:	CALL	0x2
0x5b:	GET_INPUT_BYTE	0x15
0x5c:	XOR
0x5d:	CALL	0x2
0x5e:	PUSH	0x31379b65
0x5f:	CMP_EQUAL
0x60:	JMP_RELATIVE_IF_ZERO	0x2
0x62:	PUSH	0x0
0x63:	GET_INPUT_BYTE	0x16
0x64:	XOR
0x65:	CALL	0x2
0x66:	GET_INPUT_BYTE	0x17
0x67:	XOR
0x68:	CALL	0x2
0x69:	GET_INPUT_BYTE	0x18
0x6a:	XOR
0x6b:	CALL	0x2
0x6c:	GET_INPUT_BYTE	0x19
0x6d:	XOR
0x6e:	CALL	0x2
0x6f:	PUSH	0xa3ca53ab
0x70:	CMP_EQUAL
0x71:	JMP_RELATIVE_IF_ZERO	0x2
0x73:	PUSH	0x0
0x74:	GET_INPUT_BYTE	0x1a
0x75:	XOR
0x76:	CALL	0x2
0x77:	GET_INPUT_BYTE	0x1b
0x78:	XOR
0x79:	CALL	0x2
0x7a:	GET_INPUT_BYTE	0x1c
0x7b:	XOR
0x7c:	CALL	0x2
0x7d:	GET_INPUT_BYTE	0x1d
0x7e:	XOR
0x7f:	CALL	0x2
0x80:	PUSH	0x911791b9
0x81:	CMP_EQUAL
0x82:	JMP_RELATIVE_IF_ZERO	0x2
0x84:	PUSH	0x0
0x85:	GET_INPUT_BYTE	0x1e
0x86:	XOR
0x87:	CALL	0x2
0x88:	GET_INPUT_BYTE	0x1f
0x89:	XOR
0x8a:	CALL	0x2
0x8b:	GET_INPUT_BYTE	0x20
0x8c:	XOR
0x8d:	CALL	0x2
0x8e:	GET_INPUT_BYTE	0x21
0x8f:	XOR
0x90:	CALL	0x2
0x91:	PUSH	0xe9da85a1
0x92:	CMP_EQUAL
0x93:	JMP_RELATIVE_IF_ZERO	0x2
0x95:	PUSH	0x0
0x96:	GET_INPUT_BYTE	0x22
0x97:	XOR
0x98:	CALL	0x2
0x99:	GET_INPUT_BYTE	0x23
0x9a:	XOR
0x9b:	CALL	0x2
0x9c:	GET_INPUT_BYTE	0x24
0x9d:	XOR
0x9e:	CALL	0x2
0x9f:	GET_INPUT_BYTE	0x25
0xa0:	XOR
0xa1:	CALL	0x2
0xa2:	PUSH	0x5a0b762d
0xa3:	CMP_EQUAL
0xa4:	JMP_RELATIVE_IF_ZERO	0x2
0xa6:	PUSH	0x0
0xa7:	GET_INPUT_BYTE	0x26
0xa8:	XOR
0xa9:	CALL	0x2
0xaa:	GET_INPUT_BYTE	0x27
0xab:	XOR
0xac:	CALL	0x2
0xad:	GET_INPUT_BYTE	0x28
0xae:	XOR
0xaf:	CALL	0x2
0xb0:	GET_INPUT_BYTE	0x29
0xb1:	XOR
0xb2:	CALL	0x2
0xb3:	PUSH	0xda0a6e01
0xb4:	CMP_EQUAL
0xb5:	JMP_RELATIVE_IF_ZERO	0x2
0xb7:	PUSH	0x0
0xb8:	GET_INPUT_BYTE	0x2a
0xb9:	XOR
0xba:	CALL	0x2
0xbb:	GET_INPUT_BYTE	0x2b
0xbc:	XOR
0xbd:	CALL	0x2
0xbe:	GET_INPUT_BYTE	0x2c
0xbf:	XOR
0xc0:	CALL	0x2
0xc1:	GET_INPUT_BYTE	0x2d
0xc2:	XOR
0xc3:	CALL	0x2
0xc4:	PUSH	0x48278985
0xc5:	CMP_EQUAL
0xc6:	JMP_RELATIVE_IF_ZERO	0x2
0xc8:	PUSH	0x0
0xc9:	GET_INPUT_BYTE	0x2e
0xca:	XOR
0xcb:	CALL	0x2
0xcc:	GET_INPUT_BYTE	0x2f
0xcd:	XOR
0xce:	CALL	0x2
0xcf:	GET_INPUT_BYTE	0x30
0xd0:	XOR
0xd1:	CALL	0x2
0xd2:	GET_INPUT_BYTE	0x31
0xd3:	XOR
0xd4:	CALL	0x2
0xd5:	PUSH	0xac6887be
0xd6:	CMP_EQUAL
0xd7:	JMP_RELATIVE_IF_ZERO	0x2
0xd9:	PUSH	0x0
0xda:	GET_INPUT_BYTE	0x32
0xdb:	XOR
0xdc:	CALL	0x2
0xdd:	GET_INPUT_BYTE	0x33
0xde:	XOR
0xdf:	CALL	0x2
0xe0:	GET_INPUT_BYTE	0x34
0xe1:	XOR
0xe2:	CALL	0x2
0xe3:	GET_INPUT_BYTE	0x35
0xe4:	XOR
0xe5:	CALL	0x2
0xe6:	PUSH	0x26a5d1bc
0xe7:	CMP_EQUAL
0xe8:	JMP_RELATIVE_IF_ZERO	0x2
0xea:	PUSH	0x0
0xeb:	GET_INPUT_BYTE	0x36
0xec:	XOR
0xed:	CALL	0x2
0xee:	GET_INPUT_BYTE	0x37
0xef:	XOR
0xf0:	CALL	0x2
0xf1:	GET_INPUT_BYTE	0x38
0xf2:	XOR
0xf3:	CALL	0x2
0xf4:	GET_INPUT_BYTE	0x39
0xf5:	XOR
0xf6:	CALL	0x2
0xf7:	PUSH	0x973db5ee
0xf8:	CMP_EQUAL
0xf9:	JMP_RELATIVE_IF_ZERO	0x2
0xfb:	EXIT
```
We can see that it contains a single function which is called repeatedly each time with a single byte from the flag. The result of the function is XOR'd to the previous result in cycles of 4, and is then compared to a constant value.
The function implementation in python is:
```
def  func(num):
	for  i  in  range(8):
		if  num  %  2:
			num  = (num  >>  1) ^  0xfff63b78
		else:
			num  >>=  1
	return  num
```
And its reverse is:
```
def  reverse(num):
	for  i  in  range(8):
		if  num  >>  31:	
			num  ^=  0xfff63b78
			num  <<=  1
			num  |=  1
		else:
			num  <<=  2
			num  &=  0xffffffff
	return  num
```
But in the end we didn't end up reversing each sequence of 4 bytes since we figured it could be pretty easily brute-forced using pypy.

The flag was: `pbctf{enjoy haccing blockchains? work for Zellic:pepega:!}`

We were pretty shocked to find out that the flag contains spaces, but I guess that's what you get for bruteforcing...
![](move_vm_bruteforce.png)