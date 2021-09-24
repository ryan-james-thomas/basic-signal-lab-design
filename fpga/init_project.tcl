################################################################################
# Vivado tcl script for building RedPitaya FPGA in non project mode
#
# Usage:
# vivado -mode batch -source red_pitaya_vivado_project_Z20.tcl -tclargs projectname
################################################################################



################################################################################
# define paths
################################################################################


set path_rtl sources/rtl
set path_sys sources/system
set path_cfg cfg


################################################################################
# list board files
################################################################################

# set_param board.repoPaths [list $path_brd]

################################################################################
# setup an in memory project
################################################################################

set part xc7z020clg400-3

create_project -part $part -force signallab ./project

################################################################################
# create PS BD (processing system block design)
################################################################################

# file was created from GUI using "write_bd_tcl -force ip/systemZ20.tcl"
# create PS BD
source                            $path_sys/systemZ20.tcl

# generate SDK files
# generate_target all [get_files    system.bd]

################################################################################
# read files:
# 1. RTL design sources
# 2. IP database files
# 3. constraints
################################################################################

add_files                         $path_rtl
add_files                         $path_sys

puts "Reading standard board constraints."
add_files -fileset constrs_1  $path_cfg/signal_lab.xdc


################################################################################
# start gui
################################################################################

# import_files -force

# update_compile_order -fileset sources_1

# set_property top red_pitaya_top [current_fileset]
