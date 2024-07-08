.PHONY: test compile

export LIBPYTHON_LOC=$(shell cocotb-config --libpython)

test_%:
	make compile_gpu
	iverilog -o build/sim.vvp -s gpu -g2012 build/gpu.v
	MODULE=test.test_$* vvp -M $$(cocotb-config --prefix)/cocotb/libs -m libcocotbvpi_icarus build/sim.vvp

unit_test_%:
	make compile_unit_test_$*
	vvp build/test_$*.vvp

coverage_unit_test_%:
	make unit_test_$*
	covered score -v build/test_$*.v -t testbench -vcd dump.vcd -o $*.ccd
	covered report -d s -o $*.cov $*.ccd

compile_gpu:
	make sv2v_alu
	sv2v -I src/* -w build/gpu.v
	echo "" >> build/gpu.v
	cat build/alu.v >> build/gpu.v
	echo '`timescale 1ns/1ns' > build/temp.v
	cat build/gpu.v >> build/temp.v
	mv build/temp.v build/gpu.v

compile_unit_test_%:
	sv2v -w build/test_$*.v unit_test/test_$*.sv src/$*.sv
	iverilog -o build/test_$*.vvp -s testbench -g2012 build/test_$*.v

sv2v_%:
	sv2v -w build/$*.v src/$*.sv

# TODO: Get gtkwave visualizaiton

show_%: %.vcd %.gtkw
	gtkwave $^
