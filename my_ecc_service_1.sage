# My ECC Service 1 Writeup:
#
#
# In order to be able to solve this challenge we need to figure out what is the value of the internal state variable.
# In order to do that we need to solve one of 16 ECC trapdoor functions that use the same secret value.
# While looking for possible attacks we noticed that one of the primes was smooth.
# When creating an EC with the 8th prime the order of the generator used in the server can be factored to numbers with the following "bit size": [2, 6, 12, 13, 14, 25, 28].
# This enabled us to find the nonce using the Pohlig–Hellman algorithm.
# All that is left after that is:
#    1. communicate with the server to get a payload
#    2. Find the nonce.
#    3. Run a modified version of the server with a hardcoded internal state
#    4. Generate the next payload and send it to the server.


BASE_P = (2, 3)
MODS = [
    942340315817634793955564145941,
    743407728032531787171577862237,
    738544131228408810877899501401,
    1259364878519558726929217176601,
    1008010020840510185943345843979,
    1091751292145929362278703826843,
    793740294757729426365912710779,
    1150777367270126864511515229247,
    763179896322263629934390422709,
    636578605918784948191113787037,
    1026431693628541431558922383259,
    1017462942498845298161486906117,
    734931478529974629373494426499,
    934230128883556339260430101091,
    960517171253207745834255748181,
    746815232752302425332893938923
]

# I calculated B using the base point.
A=-3
B=7
x=2
y=3
assert(y**2==x**3+A*x+B)

# Get a payload from the server and parse it
payload = "0203ce5136025013e71305ef5cfa6fe9555f0c678dc11302ec0abb4c706e1477a1e4856205a39f05901bfa671320aaff3e07d3c1752d8fa525499f73af610b6af5aa34035241c93fc8d06805ed9500662e3f9cae2d7a1daa069acee93d9894cfbad403c6fb03acf1e33ccf23fbd04e5917c200d23d96d81e3eddb724e0254d0273358282561f21247c1260ac0603161ab8453a94b42b3fe67607d8a08045699901d1a2823bb70421b38a7a92abff653760fc670520f92a017ce227c837a2e8e4070d98feab2fe3151ef94bb2e404a0e215b818ef21e6b95991f6"
key = eval("0x"+payload[2*2:2*10])
xs = [eval("0x"+payload[2*10+i*2*13:2*10+(i+1)*2*13]) for i in range(16)]


moduli = []
remi = []

for i in range(len(xs)):
    M = MODS[i]
    E = EllipticCurve(Integers(M),[0,0,0,A,B])
    P = E.point(BASE_P)
    x = mod(xs[i], MODS[i])
    y = (x**3 + A*x + B).sqrt()
    Q = E.point((xs[i],y))
    facs = list(factor(P.order()))
    # Print the size of the factors of the order to find a smooth modulo
    print(i, [f[0].nbits() for f in facs])
    
    # Use Pohlig–Hellman on the smooth modulo
    if i==7:
        for fac in facs:
            P0 = P*ZZ(P.order()/fac[0])
            Q0 = Q*ZZ(P.order()/fac[0])
            moduli.append(fac[0])
            remi.append(discrete_log(Q0,P0, operation = '+'))
        nonce = crt(remi, moduli)
        print("nonce:", nonce)
        assert(nonce.nbits()>70)
        assert(nonce.nbits()<81)

