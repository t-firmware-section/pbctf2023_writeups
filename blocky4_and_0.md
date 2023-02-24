# Blocky0 and Blocky4 Writeups

## Blocky0
If the program gets "gimmeflag" it gives the encoded flag so:
Just encoded:
```
> E
> gimmeflag
{result}
> D
> {result}
```


## Blocky4
blocky4 was a crypto challange, there is a server that randomly generates a key, then using the key:
prints the encrypted flag,
allows for: input_plain_text from user -> encrypted cipher text using key.

So basically we need a plain_text attack on this encryption to find the key.

The encryption is very similiar to AES, just uses a 144 bit key, weird key expansion, and weird add_key.
So just looked for a 4 round attack on AES and hoped it will work on this encryption.

Implemented this [article](https://www.davidwong.fr/blockbreakers/square_2_attack4rounds.html)

Wasn't sure if the persistent structure after 3 rounds for aes will apply to this encryption also so just tried and hoped for the best.
The reverse for 1 byte with the corresponding key byte:
```
    def reverse1(self, byte, key):
        sks = GF(key)

        c = GF(byte)
        c = c - sks
        c = INV_SBOX[c]
        return c.to_int()
```
To check if the guess was correct, we reverse all the 256 samples with the same key and on the result bytes:
```
def is_guess_correct(reversed_bytes: Iterable[int]) -> bool:
    r = GF(0)
    r_good = GF(0)
    for i in reversed_bytes:
        r += GF(i)
    return r == r_good
```

to generate the dataset, there was a timeout so had to merge 2 queries to a single 1 so we can have 2 delta_sets (when having only 1 delta set I always got more than 1 possible answer):
```
def encrypt_delta_set(delta_set):
    global s
    result = []
    for i in range(0, len(delta_set), 2):
        enc = b""
        if i < len(delta_set) - 1:
            a = np.concatenate((np.array(delta_set[i]).ravel(), np.array(delta_set[i+1]).ravel()))
        else:
            a = np.array(delta_set[i]).ravel()
        text_plain = bytearray()
        for b in a:
            text_plain.append(b)
        if IS_SERVER:
            print(f"Sending: {binascii.hexlify(text_plain)}")
            s.sendall(binascii.hexlify(text_plain) + b"\n")
            enc = s.recv(1024)
            print(f"Recieved: {enc}")
            enc = enc[8:-3].decode()
            print(f"Recieved: {enc}")
            enc = bytearray.fromhex(enc)
        else:
            for j in range(0, len(text_plain), 9):
                enc += cipher.encrypt(text_plain[j:j+9])
        enc_array = []
        for b in enc:
            enc_array.append(b)
        result.append(np.reshape(enc_array[:9], (3, 3)))
        if i < len(delta_set) - 1:
            result.append(np.reshape(enc_array[9:], (3, 3)))

    return result
```
to get the first key for the last key that was found:
just need to reverse the operation that is used to calculate the next key (key[i] = key[i-1] + SBOX(key[i-9]))
```
def get_first_key(last_key, rounds):
    b = [GF(x) for x in last_key]
    b = b[::-1]
    for i in range((rounds-1)*9):
        b.append(INV_SBOX[b[-9] - b[-8]])
    
    result = []
    for i in b[::-1][:9]:
        print(hex(i.to_int()), end=" ")
        result.append(i.to_int())
    print()
    return bytearray(result)
```