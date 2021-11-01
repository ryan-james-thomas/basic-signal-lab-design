# from bitstring import BitArray
# import serial
import time
import types
import subprocess
import warnings
import struct

MEM_ADDR = 0x40000000

def write(data,header):
    addr = MEM_ADDR + data[0]
    response = {"err":False,"errMsg":"","data":b''}

    if header["mode"] == "fetch ram":
        cmd = ['./fetchRAM',format(header["numSamples"])]
        if ("print" in header) and (header["print"]):
            print("Command: ",cmd)
        result = subprocess.run(cmd,stdout=subprocess.PIPE)

        if result.returncode == 0:
            fid = open("SavedData.bin","rb")
            response["data"] = fid.read()
            fid.close()

    else:
        if header["mode"] == "write":
            cmd = ['monitor',format(addr),'0x' + '{:0>8x}'.format(data[1])]
        elif header["mode"] == "read":
            cmd = ['monitor',format(addr)]
        elif header["mode"] == "set output gain":
            cmd = ['./setGain','-o','-p',format(header['port']),'-v',format(header['value'])]
        elif header["mode"] == "set input gain":
            cmd = ['./setGain','-i','-p',format(header['port']),'-v',format(header['value'])]
        elif header["mode"] == "set coupling":
            cmd = ['./setGain','-c','-p',format(header['port']),'-v',format(header['value'])]

        if ("print" in header) and (header["print"]):
                print("Command: ",cmd)

        result = subprocess.run(cmd,stdout=subprocess.PIPE)
        if result.returncode == 0:
            data = result.stdout.decode('ascii').rstrip()
            if len(data) > 0:
                buf = struct.pack("<I",int(data,16))
            else:
                buf = b''
            response["data"] += buf

    
    if result.returncode != 0:
        response = {"err":True,"errMsg":"Bus error","data":[]}

    return response
        


    
        
