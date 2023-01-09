# Ibex Demo System

This an example RISC-V SoC targeting the Arty-A7 FPGA board. It comprises the
[lowRISC Ibex core](https://www.github.com/lowrisc/ibex) along with the
following features:

* RISC-V debug support (using the [PULP RISC-V Debug Module](https://github.com/pulp-platform/riscv-dbg))
* A UART
* GPIO (output only for now)
* Timer
* SPI
* A basic peripheral to write ASCII output to a file and halt simulation from software

Debug can be used via a USB connection to the Arty-A7 board. No external JTAG
probe is required.

## Nix Setup

An alternative system for installing all of the project dependencies is
provided using the Nix package manager. Once installed and the dependencies
are fetched from the internet, you can enter a shell with all of the software
required for building by running the command `nix develop .#labenv` in the root
directory of the project. To leave this environment, simply run `exit`.

### Installing
#### Installing Nix
```bash
# Run the reccommended nix multi-user installation
# https://nixos.org/download.html
# This is interactive, just follow the prompts
sh <(curl -L https://nixos.org/nix/install) --daemon

# Add some global configuration to nix to make use of the flakes and CLI experimental features.
cat <<EOF > $HOME/.config/nix/nix.conf
experimental-features = nix-command flakes
EOF

# You may now need to reload your shell, but check that nix is working by running this:
nix --version
> nix (Nix) 2.12.0
```
#### Installing Vivado using Nix
```bash
# Go to the Xilinx.com website
# https://www.xilinx.com/support/download.html
# Download the 2022.2 Unified Installer for Linux
# The link looks like:
# <Xilinx Unified Installer 2022.2: Linux Self Extracting Web Installer (BIN - 271.02 MB)>
# The download link will be similar to:
# https://www.xilinx.com/member/forms/download/xef.html?filename=Xilinx_Unified_2022.2_1014_8888_Lin64.bin
# You will need to register on the website to download this file.

# Once the download is complete...
cd <location/of/downloaded/file>

# Extract the installer to a local temporary directory
local PREFIX=/tmp/xilinx
local VERSION=2022.2
local INSTALLER="Xilinx_Unified_${VERSION}_0420_0327_Lin64.bin"  # This should match the download
local INSTALLER_EXTRACTED="${PREFIX}/extracted"
sudo mkdir $PREFIX
sudo chown -R $USER:$USER $PREFIX $INSTALLER
sudo $INSTALLER --keep --noexec --target $PREFIX

# Now run the installer to create a bundler installer with the devices we need.
local INSTALLER_BUNDLED="$PREFIX/bundled"
pushd PREFIX
./xsetup
```

- Run the installer graphically
  1. Page '<LANDING_PAGE>'
     1. Select 'Next >'
  2. Page 'Select Install Type'
     1. Enter email/password for 'User Authentication' (register on Xilinx.com)
     2. Select the radio-box 'Download Image (Install Seperately)'
     3. Select the download directory as '$INSTALLER_BUNDLED' (See above)
     4. Under 'Download fields to create full image for selected platform(s)', select 'Linux' only.
     5. Under 'Image Contents', select 'Selected Product Only'
     6. Select 'Next >'
  3. Page 'Select Product to Install'
     1. Select the radio-box 'Vivado' only
     2. Select 'Next >'
  4. Page 'Select Edition to Install'
     1. Select the radio-box 'Vivado ML Standard'
     2. Select 'Next >'
  5. Page 'Vivado ML Standard'
     1. Ensure only the following boxes are selected....
        1. Design Tools - Vivado Design Suite - {Vivado, Vitis HLS}
        2. Devices - Production Devices - 7 Series - {Artix7, Kintex7, Spartan7}
        3. Installation Options
     2. Select 'Next >'
  6. Page 'Download Summary'
     1. Select 'Download'

- Now wait for the download to complete (approx 13GB)

```bash
# Now we have created a bundled installer for Vivado, we need to add this to the nix store

# The easiest way to get the data into the nix store is by creating an archive...
# (You may need to install 'pigz' for this step, e.g. 'sudo apt install pigz')
local BUNDLED_ARCHIVE="$PREFIX/vivado_bundled.tar.gz"
tar cf $BUNDLED_ARCHIVE -I pigz --directory=$(dirname $INSTALLER_BUNDLED) ./$(basename $INSTALLER_BUNDLED)

# Now add using 'nix-prefetch-url'
VIVADO_BUNDLED_HASH=$(nix-prefetch-url --type sha256 file:$BUNDLED_ARCHIVE)
  > path is /nix/store/pfw6kxlmd4bsj9ml7j4i1a6dbi3dhff8-vivado_bundled.tar.gz

# The value of this has will be needed for the next step.
echo $VIVADO_BUNDLED_HAS
```

#### Add udev rules for our device
These are needed for the programmer to access the development board.
```bash
sudo cat <<EOF > /etc/udev/rules.d/90-arty-a7.rules
# Future Technology Devices International, Ltd FT2232C/D/H Dual UART/FIFO IC
# used on Digilent boards
ACTION=="add|change", SUBSYSTEM=="usb|tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", ATTRS{manufacturer}=="Digilent", MODE="0666"

# Future Technology Devices International, Ltd FT232 Serial (UART) IC
ACTION=="add|change", SUBSYSTEM=="usb|tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", MODE="0666"
EOF
```
Run the following to reload the rules...

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

#### Install and activate our environment
Finally, we can use the nix flake.nix recipe to build our environment. This will
use the vivado installer we added to the /nix/store above to install vivado within
our sandboxed environment, and then add it's PATH to our own once installed.
```bash
git clone git@github.com:lowRISC/ibex-demo-system.git
cd ibex-demo-system

nix develop .#labenv
# This will take a while, maybe 10 mins...

# Once it completes, you will be in a shell with all the tools required to do the lab.

# To exit this shell environment when you are done, simply run
exit
```

## Software Requirements

* Xilinx Vivado - https://www.xilinx.com/support/download.html
* rv32imc GCC toolchain - lowRISC provides one:
  https://github.com/lowRISC/lowrisc-toolchains/releases
  (For example: `lowrisc-toolchain-rv32imcb-20220524-1.tar.xz`)
* cmake
* python3 - Additional python dependencies in python-requirements.txt installed
  with pip
* openocd (version 0.11.0 or above)
* screen
* srecord

To install python dependencies use pip, you may wish to do this inside a virtual
environment to avoid disturbing you current python setup (note it uses a lowRISC
fork of edalize and FuseSoC so if you already use these a virtual environment is
recommended)

```bash
# Setup python venv
python3 -m venv .venv
source .venv/bin/activate

# Install python requirements
pip3 install -r python-requirements.txt
```

You may need to run the last command twice if you get the following error:
`ERROR: Failed building wheel for fusesoc`

## Building Software

First the software must be built. This is provide an initial binary for the FPGA
build.

```
mkdir sw/build
pushd sw/build
cmake ../
make
popd
```

Note the FPGA build relies on a fixed path to the initial binary (blank.vmem) so
if you want to create your build directory elsewhere you need to adjust the path
in `ibex_demo_system.core`

## Building FPGA
FuseSoC handles the FPGA build. Vivado tools must be setup beforehand. From the
repository root:

```
module load xilinx/vivado/latest
source venv/bin/activate
fusesoc --cores-root=. run --target=synth --setup --build lowrisc:ibex:demo_system
```

## Programming FPGA
To program FPGAs the user using Vivado typically needs to have permissions to access USB devices connected to the PC. Depending on your security policy you can take different steps to enable this access. One way of doing so is given in the udev rule outlined below.

To do so, create a file named `/etc/udev/rules.d/90-arty-a7.rules` and add the following content to it:

```
# Future Technology Devices International, Ltd FT2232C/D/H Dual UART/FIFO IC
# used on Digilent boards
ACTION=="add|change", SUBSYSTEM=="usb|tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", ATTRS{manufacturer}=="Digilent", MODE="0666"

# Future Technology Devices International, Ltd FT232 Serial (UART) IC
ACTION=="add|change", SUBSYSTEM=="usb|tty", ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6001", MODE="0666"
```

Run the following to reload the rules...

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger
```

And if your A7 is already connected, unplug your device and plug it back in.

To program the FPGA, either use FuseSoC again

```
fusesoc --cores-root=. run --target=synth --run lowrisc:ibex:demo_system

# If the above does not work, try executing the programming operation manually with..
make -C ./build/lowrisc_ibex_demo_system_0/synth-vivado/ pgm
```

Or use the Vivado GUI

```
make -C ./build/lowrisc_ibex_demo_system_0/synth-vivado/ build-gui
```

Inside Vivado you do not have to run the synthesis, the implementation or generate the bitstream.
Simply click on "Open Hardware Manager", then on "Auto Connect" and finally on "Program Device".

## Loading an application to the programmed FPGA

The util/load_demo_system.sh script can be used to load and run an application. You
can choose to immediately run it or begin halted, allowing you to attach a
debugger.

```bash
# Run demo
./util/load_demo_system.sh run ./sw/build/demo/demo

# Load demo and start halted awaiting a debugger
./util/load_demo_system.sh halt ./sw/build/demo/demo
```

To view terminal output use screen:

```bash
# Look in /dev to see available ttyUSB devices
screen /dev/ttyUSB1 115200
```

If you see an immediate `[screen is terminating]`, it may mean that you need super user rights.
In this case, you may try using `sudo`.

To exit from the `screen` command, you should press control and a together, then release these two keys and press d.

## Debugging an application

Either load an application and halt (see above) or start a new OpenOCD instance

```
openocd -f util/arty-a7-openocd-cfg.tcl
```

Then run GDB against the running binary and connect to localhost:3333 as a
remote target

```
riscv32-unknown-elf-gdb ./sw/build/demo/demo

(gdb) target extended-remote localhost:3333
```
## Building Simulation

The Demo System simulator binary can be built via FuseSoC. From the Ibex
repository root run:

```
fusesoc --cores-root=. run --target=sim --tool=verilator --setup --build lowrisc:ibex:demo_system
```
## Running the Simulator

Having built the simulator and software, from the Ibex repository root run:

```
./build/lowrisc_ibex_demo_system_0/sim-verilator/Vibex_demo_system [-t] --meminit=ram,<sw_elf_file>
```

`<sw_elf_file>` should be a path to an ELF file  (or alternatively a vmem file)
built as described above. Use `./sw/build/demo/demo` to run the `demo`
binary.

Pass `-t` to get an FST trace of execution that can be viewed with
[GTKWave](http://gtkwave.sourceforge.net/).

```
Simulation statistics
=====================
Executed cycles:  5899491
Wallclock time:   1.934 s
Simulation speed: 3.05041e+06 cycles/s (3050.41 kHz)

Performance Counters
====================
Cycles:                     457
NONE:                       0
Instructions Retired:       296
LSU Busy:                   108
Fetch Wait:                 20
Loads:                      53
Stores:                     55
Jumps:                      21
Conditional Branches:       12
Taken Conditional Branches: 7
Compressed Instructions:    164
Multiply Wait:              0
Divide Wait:                0
```
