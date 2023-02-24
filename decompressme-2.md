# Decompressme-2

## Analysing the traffic
We started by inspecting the traffic we received in the pcap file. Each packet contained 70 bytes and tried to discern if it was all data or maybe scrambled headers and data. 
We exported the data from Wireshark to a binary file.

## Binwalk
We tired to look for common headers using Binwalk with no success.
When we tried entropy analysing we saw that the beginning of the file had a completely different level. We concluded that it was the silence at the beginning of the recording. 

## Format analysis
We decided to focus on the silence at the beginning of the file to study the structure of the packets.
Early on we identified three words followed by data. 
In the silence part the second and third words had small values (+-5). 
We concluded that the first word is the master gain and the two other words are probably right and left values. 

## Format comparison
We decided to compare the data to other known formats of audio compression. After looking at many different types we arrives at the conclusion that the protocol was custom or at least a variation on known algorithms.
We even wrote a script to generate .au headers and listened to all the outputs but with no success.

## Custom format design
We tried a simple approach at first. Add the first word to all the data in the packet, and then add the second word to even words and the third word to odd words. We also xored the data with a common magic (0x55).
We took the output and played it in Audacity media player and set the frequency to the packet frequency.
We got some really rough sounding Rickroll !

## Improving the quality
Using the plethora of audio tools in Audacity media player we were able to isolate the speech over all the noise and background music and get the flag!