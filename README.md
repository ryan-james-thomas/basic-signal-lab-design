# Description

This is a bare-bones design for the Red Pitaya SIGNALlab 250-12 device, and is meant as a starting point for more complex projects that do not use the Red Pitaya FPGA images.  It's a demonstration of how to write data to the DACs and read data from the ADCs, as well as how to interface the programmable logic with the operating system.

# Set up

## Starting the SIGNALlab

Connect the SIGNALlab to power and connect the device to the local network using an ethernet cable.  Log into the device using SSH with the user name `root` and password `root` using the hostname `rp-{MAC}.local` where `{MAC}` is the last 6 characters in the device's MAC address - this will be printed on the ethernet connector of the device.

### First use

Copy over the files in the 'software/' directory ending in '.py' and in '.c', the file 'get_ip.sh', and the file 'Makefile' using either `scp` (from a terminal on your computer) or your favourite GUI (I recommend WinSCP for Windows).  You will also need to copy over the file 'fpga/system_wrapper.bit' which is the device configuration file.  If using `scp` from the command line, navigate to the main project directory on your computer and use
```
scp fpga/system_wrapper.bit software/*.py software/get_ip.sh software/*.c root@rp-{MAC}.local:/root/
```
and give your password as necessary.  You can move these files to a different directory on the RP after they have been copied.

Next, change the execution privileges of `get_ip.sh` using `chmod a+x get_ip.sh`.  Check that running `./get_ip.sh` produces a single IP address.  There may be more than one IP address -- you're looking for one that has tags 'global' and 'dynamic'.  Here is the output from one such device:
```
root@rp-f0919a:~# ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc pfifo_fast state UP group default qlen 1000
    link/ether 00:26:32:f0:91:9a brd ff:ff:ff:ff:ff:ff
    inet 169.254.176.82/16 brd 169.254.255.255 scope link eth0
       valid_lft forever preferred_lft forever
    inet 192.168.1.109/24 brd 192.168.1.255 scope global dynamic eth0
       valid_lft 77723sec preferred_lft 77723sec
3: sit0@NONE: <NOARP> mtu 1480 qdisc noop state DOWN group default qlen 1
    link/sit 0.0.0.0 brd 0.0.0.0
```
In this case the one we want is the address `192.168.1.109`.

Finally, compile the C program `fetchRAM.c` using `gcc -o fetchRAM fetchRAM.c`.  This will automatically be executable.  You will also need to create the file 'setGain' using 'make setGain' which will use the file 'Makefile' to do the appropriate linking to various libraries.  In order to use this program, you will need to have the correct library in your path.  You can either run the command
```
export LD_LIBRARY_PATH=/opt/redpitaya/lib
```
every time you open a new terminal, or you can add that line to the end of your '.bashrc' file so that it is automatically loaded every time a new terminal is started.

### After a reboot or power-on

You will need to re-configure the FPGA and start the Python socket server after a reboot.  To re-configure the FPGA run the command
```
cat system_wrapper.bit > /dev/xdevcfg
```

To start the Python socket server run
```
python3 appserver.py &
```
This should print a line telling you the job number and process ID  as, for example, `[1] 5760`, and a line telling you that it is 'Listening on' and then an address and port number.  The program will not block the command line and will run in the background as long as the SSH session is active (The ampersand & at the end tells the shell to run the program in the background).  To stop the server, run the command `fg 1` where `1` is the job number and then hit 'CTRL-C' to send a keyboard interrupt.

### After starting/restarting the SSH session

You will need to check that the socket server is running.  Run the command
```
ps -ef | grep appserver.py
```
This will print out a list of processes that match the pattern `appserver.py`.  One of these might be the `grep` process itself -- not especially useful -- but one might be the socket server.  Here's an example output:
```
root      5768  5738  7 00:59 pts/0    00:00:00 python3 appserver.py
root      5775  5738  0 01:00 pts/0    00:00:00 grep --color=auto appserver.py
```
The first entry is the actual socket server process and the second one is the `grep` process.  If you need to stop the server, and it is not in the jobs list (run using `jobs`), then you can kill the process using `kill -15 5768` where `5768` is the process ID of the process (the first number in the entry above).  

If you want the server to run you don't need to do anything.  If the server is not running, start it using `python3 appserver.py`.  

# Use

It's best to just look at the code to figure out what's going on, as this is not meant to be a finished project.

# Creating the project

To create the Vivado project, clone the repository to a directory on your computer, open Vivado, navigate to the fpga/ directory (use `pwd` in the TCL console to determine your current directory and `cd` to navigate, just like in Bash), and then run `source signallab.tcl`.  This should create the project with no errors.  It may not correctly assign the AXI addresses, so you will need to open the address editor and assign the `PS7/AXI_Parse_0/s_axi` interface the address range `0x4000_000` to `0x7fff_ffff`.

