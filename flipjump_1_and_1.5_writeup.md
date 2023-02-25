# Flipjump 1 (+ 1.5)

Flipjump 1 was a misc. (AKA reversing, apparently) challenge in PBCTF 2023.
It came in two versions - Flipjump 1 and Flipjump 1.5. The former contained an unintended solution, but the difference between the two is small.

## Introduction

> What could you possibly do with a flip and jump?

The handout for this challenge was a binary (with a corresponding libc for flipjump 2) and a `nc` to a server running the binary.

```
Let's play a 2-player bit flip game using a bit flip VM.
Enter code length:
64
Enter code:
```

The server seems to be hosting some sort of game, asking the player to input a length of code and the code itself.

We also receives the game's binary, which we can use to understand how the game works.

## The Rules of the Game

As we begin looking for a way to get a flag, we can see that the game runs in a loop, at the end of which it prompts us to play again and checks whether 69 rounds were won. Upon reaching 69 wins the flag is printed. After a loss, the game exits. This leads us to assume that we need to find a way to consistently (and automatically) win the game.

A round of the game starts off by allocating a 16-bit buffer and passing it to a function called `randomize_board`, which randomizes the contents of the buffer and also returns a random number in the range of 0 to 15. We'll refer to the randomized buffer as the "board" and the 4-bit random number as the "secret".

The game then proceeds to call a function called `run_player` with our board and secret, as well as a pointer to `p1_code`.
It then proceeds to take the return value of this function (N) and uses it as an index into the board, flipping the N'th bit of the board. This flip is also printed out in the form of:

```c
printf(
    "Flip[%ld] Bit %ld %c->%c\n",
    p1_res / 8, // Board byte
    p1_res % 8, // Bit in byte
    _param3,    // original bit
    _param4     // flipped bit
);
```

Finally, the function `run_player` is run again, this time with the same board (but with a flipped bit), `p2_code`, and `NULL` instead of our secret, and the result is compared to our secret to determine a victory.

> We can take a look at the difference between the 1 and 1.5 versions to see the patch to eliminate the unintended solution. The entire patch is that the order of the printing of the bit-flip message and the execution of the second turn is switched around, which can hint at the fact that we can use this message as information to control the second player's turn to cheese our way to a flag :D

To understand how a turn looks, we can look at the `run_player` function. We can see that we begin by using prompting the player for a size for the allocated code buffer, then filling the code buffer with input from the player. Throughout, our code buffer seems to be treated as an array of 64-bit slots.

After this, two changes are made to our code buffer.
First, every bit from our 16-bit board is placed into every other slot in the last 32 slots of our buffer.
Second, if the secret was passed (which it is only in the first player's turn), it is placed into the slot that preceeds the board slots.

After the setup, a function called `run_vm` is run (which presumably executes our "code") and after the function returns we return the 4 bits from the slot into which our secret was placed.

To summarize, the first player's turn starts by asking the player to input a code buffer, which is initialized like so (each block is a 64-bit slot):

```
[ p1 code ] [ p1 code ] ...
[ secret (output) ]
[ p1 code ] [ board bit 0 ] ...
[ p1 code ] [ board bit 15 ]
```

The 4-bit content of the output slot is used to flip a bit in the board.

The second player's turn begins by asking the player for code again, and the buffer is initialized like this:

```
[ p2 code ] [ p2 code ] ...
[ p2 code (output) ]
[ p2 code ] [ board bit 0 ] ...
[ p2 code] [flipped board bit N] ...
[ p2 code ] [ board bit 15 ]
```

And to win, we need to find a way to use what seems to be some sort of code instructions to change the value of the output slot to be the secret.

## The VM

So, how does running code work in this "bit flip VM"?

`run_vm` is called with a struct containing the pointer to our code buffer, its size and a yet-unknown integer which is initialized to zero (we'll refer to it at the code struct)

We can see that `run_vm` runs in a loop. First, two consecutive 64-bit slots from the code buffer are saved. The slots are the ones pointed to by the third member of the code struct, which seems to be an index to pairs of slots, rather than single ones. The size of the buffer in bits is also saved.

```c
slot1 = *(_QWORD *)(a_ctx->code + 16LL * a_ctx->unk);
slot2 = *(_QWORD *)(a_ctx->code + 8 * (2 * a_ctx->unk + 1LL));
memsize_in_bits = 8LL * a_ctx->code_bytes_len;
```

Next, we exit the VM only if the value of the first slot is greater than the size in bits.

```c
if ( slot1 >= memsize_in_bits )
    break;
```

Then, the first slot is used to flip a bit in the code buffer. The first slot seems to be an index to the bits of the buffer, and it signifies which bit in the buffer to flip. Earlier, we finished the run if our bit-flip index was outside the range of the buffer.

```c
*(_BYTE *)(slot1 / 8 + a_ctx->code) = (1 << (slot1 & 7)) ^ *(_BYTE *)(a_ctx->code + slot1 / 8);
```

And finally, the third member of the code struct is updated with the value of the second slot, which seems to be the index of the next instruction to run in the next iteration.

```c
a_ctx->unk = slot2;
```

To summarize, our buffer seems to be made up of 128-bit "instructions" for the VM, which consist of an index to flip a bit in the buffer and the index of the next instruction to run.

```c
struct instruction {
    _QWORD bitflip_index;
    _QWORD next_inst;
}

struct code {
    _BYTE * code;
    _QWORD code_bytes_len;
    _DWORD next_inst;
}
```

So now that we know how the game works, we can understand what we need to do.

In the first player's turn, the code buffer is initialized as shown above, and our only output is the state of the 4-bit output slot which controls which bit of the 16-bit board is flipped. This change is reflected in the second player's turn in the last 32 slots (16 instructions) of the code buffer.

This means that we need to find a way to encode the secret in the first player's bitflip, and to decode the secret from the code buffer's state in the second player's turn and recreate it in the output slot to win the round.

## Cheesy (unintended) solution

First, as was hinted earlier, there's an unintended solution in Flipjump 1 which is not present in Flipjump 1.5, and is somehow fixed by printing the index of the bitflip in the board after the second player's turn rather than before it. Now that we know how the game works, exploiting this is simple.

If we don't cause any change in the output slot, the index of the bitflip is equal to the secret, which is printed to us before the second player's turn.
Now that we know the secret, we can initialize the second player's code buffer to contain the secret in the output slot (which remains untouched) and immediately exit, which counts as a win!

The following code snippet from the solution script shows the board setup for both players:

```python
def p1_turn():
    code = [
        (END_VM_BIT, 0),
    ]

    output = 0

    board = [0] * 32

    send_turn(code, output, board)

# In between the turns, the output message is parsed to extract the bitflip's index
FLIP_FMT = r"Flip\[(?P<byte>\d+)\] Bit (?P<bit>\d+) (?P<old>.)->(?P<new>.)\n"

def p2_turn(bitflip_byte, bitflip_bit):
    code = [
        (END_VM_BIT, 0),
    ]

    output = bitflip_byte * 8 + bitflip_bit

    board = [0] * 32

    send_turn(code, output, board)
```

And now, for flipjump 1.5, we must do the same thing but without knowing which bit was flipped.

## Real solution

The solution works by encoding the secret in the state of the board during the first player's turn in a way that can be symmetrically decoded in the second player's turn.

First, in the first player's turn, for each bit in the board (as it appears at the end of our code buffer), if it is set, XOR the output slot (which is initialized to our secret) with the bit index.

If we mark the bits of the board as `b_i`, and the secret as `S`, the value of the first player’s output (`N`) is:

```c
N = S ^ b_0 * 0 ^ b_1 * 1 ^ … ^ b_15 * 15
```

As `N` is the index of the flipped bit in the board between the turns, our board becomes:

```c
b_0, …, ~b_N, …, b_15
```

For our second player’s turn, we perform exactly the same computation, XOR'ing the index of each set bit with the value of the output slot, only this time it is initialized to 0. The result of this calculation is equal to:

```c
b_0 * 0 ^ … ^ ~b_N * N ^ … ^ b_15 * 15
```

Note that flipping the N'th bit of the board results in our result being XOR'ed by `N`:

```c
~b_N * N = b_N * N ^ N
```

So the result of the second player’s turn can be reduced to:

```c
b_0 * 0 ^ … ^ (b_N * N ^ N) ^ … ^ b_15 * 15 =

(b_0 * 0 ^ … ^ b_15 * 15) ^ N =

(N ^ S) ^ N =

S
```

So we get the desired result, and with exactly the same code for both players.

## Implementation

To implement the algorithm using the bitflip VM, we can set up our code using a XOR-by-constant primitive and an “if” primitive (in our case a 2 case jump table).

First, we want a way to XOR the output by a constant (0 through 15) in the case that the corresponding bit is set.

This can be simply done by flipping the output by each bit of the constant (for example, to XOR by 11 we would flip bits 0, 1 and 3 of the output slot). This can be done in a constant number of commands, at most 4.

To check whether a bit is set, we can set up a jump table, starting at address N (for the sake of convenience let’s assume N is aligned to a large power of 2, say 0x100), that looks like so:

```c
[ 0 | next_jump ]

[ output+0 | N+2 ]

[ output+1 | N+3 ]

[ output+3 | next_jump ]
```

To check whether a bit is 0 or 1 and XOR by a constant using this bit, we simply need to XOR the slot holding the bit by N and jump to it as an instruction (note that the bits holding the board are of the form `[ 0 | b_i ]` so this is possible). If it was 0 it will jump to N and continue immediately, and if it was 1 it will jump to N+1 and XOR the output by i then continue.

Our solution first sets up 16 jump tables, one for each bit, and sets up each of the board slots to jump to its corresponding jump table, then jumps to the first board slot, with each jump table ending in a jump to the next bit of the board, with the last one exiting by trying to flip a bit outside of the code’s range.

And after sending the code 69 times, we get the flag!
