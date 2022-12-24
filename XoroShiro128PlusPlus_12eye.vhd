-- VHDL is a HDL or a Hardware Description Language. It is used to describe circuits with code.
-- In VHDL, comments start with --
-- Everything will eventually be moved to Verilog, another HDL that is easier to read and work with.
-- This file is the top file. You can think of this like the main function.

LIBRARY ieee; -- This is to set up future imports.

USE ieee.std_logic_1164.ALL; -- This is an import so things like std_logic vector work.
USE ieee.numeric_std.ALL; -- This is an import so things like unsigned work.
LIBRARY work; -- This is the "package" for the current project.

ENTITY XoroShiro128PlusPlus_12eye IS -- This is an entity, you can think of it like a function.
	GENERIC (-- I use generics here as a "easy" way to change things like the starting seed and how many instances I'm using.
		start_seed_offset : UNSIGNED(63 DOWNTO 0) := X"0003000000000000"; -- This is the starting seed in hex.
		instances         : INTEGER := 40; -- This is how many instances are used. 1 instance = 1 seed per cycle. 50 instances = 50 seeds per cycle.
		instance_adder    : UNSIGNED := X"28" -- This is the increment value for the seeds in hex. It is the same value as instances but represented as unsigned. This might not be needed.
	);
	PORT (-- Ports are like parameters in functions.
		clk_in1 : IN STD_LOGIC; -- This is the input clock. It is a physical input going to the FPGA from a clock source.
		UART_TX : OUT STD_LOGIC; -- This is the UART TX pin. UART is serial communication, which is why this is a single pin and not multiple pins. It is a physical output going from the FPGA to another device. Seeds get sent over this.
		led_r   : OUT STD_LOGIC; -- This is a red LED. It is used for showing the status of things. It has no impact on seeds.
		led_g   : OUT STD_LOGIC -- Same as above.
	);

END XoroShiro128PlusPlus_12eye; -- This is the end of the function parameters.

ARCHITECTURE arch OF XoroShiro128PlusPlus_12eye IS -- This is the start of the architecture. This describes what signals, components and other things are part of this entity.
	TYPE arr1 IS ARRAY(0 TO 63) OF UNSIGNED(63 DOWNTO 0); -- This is a 64 element array of 64 bit unsigned values. This holds the seed input for the instances.
	TYPE arr2 IS ARRAY(0 TO 63) OF STD_LOGIC; -- This is a 64 element array of 1 bit values. This holds the validity of a seed (aka if it is a 12 eye or not).
	-- The reason 64 is used is because the "compiler" optimizes away the unused elements.

	COMPONENT clk_wiz_0 -- This is the component that turns the input clock frequency into two different output frequencies to be used for the rest of the FPGA. This is how CPUs and GPUs work as well. Your CPU can turn a 25MHz input clock into a 4.0GHz output clock. This is an oversimplification but I cannot think of a better way to explain it in a single comment.
		PORT (
			clk_in1  : IN STD_LOGIC; -- This is the input clock.
			clk_out1 : OUT STD_LOGIC; -- This is the first output clock. It is used for the main seedfinding stuff.
			clk_out2 : OUT STD_LOGIC -- This is the second output clock. It is used for UART.
		);
	END COMPONENT;

	COMPONENT filter -- This is the component that does the filtering for finding 12 eyes.
		PORT (
			CLK        : IN STD_LOGIC; -- This is the input clock for the component.
			seed_input : IN UNSIGNED(63 DOWNTO 0); -- This is the seed input. It is 64 bits.
			is_valid   : OUT STD_LOGIC -- This is the output that tells us if the seed is a 12 eye or not. It is 1 bit.
		);
	END COMPONENT;

	COMPONENT comm_uart -- This is the UART component. It is used for sending valid seeds to another device.
		PORT (
			comm_clk      : IN STD_LOGIC; -- This is the input clock used for UART
			seed_clk      : IN STD_LOGIC; -- This is the input clock that lets this component transfer data between the areas that have a different clock frequency.
			uart_tx       : OUT STD_LOGIC; -- This is the output that contains the serial data containing the valid seed.
			is_seed_valid : IN STD_LOGIC; -- This is the input bit that tells this component to write the seed to the FIFO queue. When this is high, the seed gets sent to us.
			seed_input    : IN STD_LOGIC_VECTOR(63 DOWNTO 0) -- This is the input seed. It is only used when the above input is high.
		);
	END COMPONENT;
 
	SIGNAL is_any_seed_valid : STD_LOGIC := '0'; -- This is a bit that tells us if ANY seed is valid. Default to 0 just to be sure.
	SIGNAL seed_clk          : STD_LOGIC; -- This is the seed clock signal.
	SIGNAL uart_clk          : STD_LOGIC; -- This is the UART clock signal
	SIGNAL temp_seed_buffer  : STD_LOGIC_VECTOR(63 DOWNTO 0); -- This is a temporary 64 bit seed buffer for sending seeds to the UART FIFO.
	SIGNAL led_g_test        : STD_LOGIC := '0'; -- This is just for the green LED. Not related to seedfinding.
	SIGNAL valid_seed        : STD_LOGIC; -- This is a singal used to tell the UART FIFO to write the seed.
	SIGNAL start_inputs      : arr1 := (start_seed_offset, start_seed_offset + x"0000000000000001", start_seed_offset + x"0000000000000002", start_seed_offset + x"0000000000000003", start_seed_offset + x"0000000000000004", start_seed_offset + x"0000000000000005", start_seed_offset + x"0000000000000006", start_seed_offset + x"0000000000000007", start_seed_offset + x"0000000000000008", start_seed_offset + x"0000000000000009", start_seed_offset + x"000000000000000A", start_seed_offset + x"000000000000000B", start_seed_offset + x"000000000000000C", start_seed_offset + x"000000000000000D", start_seed_offset + x"000000000000000E", start_seed_offset + x"000000000000000F", start_seed_offset + x"0000000000000010", start_seed_offset + x"0000000000000011", start_seed_offset + x"0000000000000012", start_seed_offset + x"0000000000000013", start_seed_offset + x"0000000000000014", start_seed_offset + x"0000000000000015", start_seed_offset + x"0000000000000016", start_seed_offset + x"0000000000000017", start_seed_offset + x"0000000000000018", start_seed_offset + x"0000000000000019", start_seed_offset + x"000000000000001A", start_seed_offset + x"000000000000001B", start_seed_offset + x"000000000000001C", start_seed_offset + x"000000000000001D", start_seed_offset + x"000000000000001E", start_seed_offset + x"000000000000001F", start_seed_offset + x"0000000000000020", start_seed_offset + x"0000000000000021", start_seed_offset + x"0000000000000022", start_seed_offset + x"0000000000000023", start_seed_offset + x"0000000000000024", start_seed_offset + x"0000000000000025", start_seed_offset + x"0000000000000026", start_seed_offset + x"0000000000000027", start_seed_offset + x"0000000000000028", start_seed_offset + x"0000000000000029", start_seed_offset + x"000000000000002A", start_seed_offset + x"000000000000002B", start_seed_offset + x"000000000000002C", start_seed_offset + x"000000000000002D", start_seed_offset + x"000000000000002E", start_seed_offset + x"000000000000002F", start_seed_offset + x"0000000000000030", start_seed_offset + x"0000000000000031", start_seed_offset + x"0000000000000032", start_seed_offset + x"0000000000000033", start_seed_offset + x"0000000000000034", start_seed_offset + x"0000000000000035", start_seed_offset + x"0000000000000036", start_seed_offset + x"0000000000000037", start_seed_offset + x"0000000000000038", start_seed_offset + x"0000000000000039", start_seed_offset + x"000000000000003A", start_seed_offset + x"000000000000003B", start_seed_offset + x"000000000000003C", start_seed_offset + x"000000000000003D", start_seed_offset + x"000000000000003E", start_seed_offset + x"000000000000003F");
	-- This signal is used to hold the seeds used for the filters.
	SIGNAL valids            : arr2 := ('0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0', '0');
    -- This signal is used to hold the valid outputs from the filters
BEGIN
	clock_component : clk_wiz_0 -- See comments above in the component declaration.
	PORT MAP(
		clk_in1  => clk_in1, 
		clk_out1 => seed_clk, 
		clk_out2 => uart_clk
	);
 
	uart_component : comm_uart -- See comments above in the component declaration.
	PORT MAP(
		comm_clk      => uart_clk, 
		seed_clk      => seed_clk, 
		uart_tx       => UART_TX, 
		is_seed_valid => valid_seed, 
		seed_input    => temp_seed_buffer
	);
 
	generate_filters : FOR I IN 0 TO instances - 1 GENERATE -- This generates n instances of the filter.
		filter_instance  : filter
		PORT MAP(
			CLK        => SEED_CLK, -- This makes the filter use the SEED_CLK for the instance clock/
			seed_input => start_inputs(I), -- This makes the seed_input the value of I in the start_inputs array.
			is_valid   => valids(I) -- Same as above.
		);
	END GENERATE generate_filters;
	PROCESS (SEED_CLK) IS -- When SEED_CLK changes, this activates. This means it activates on rising edge and falling edge.
	BEGIN
		led_r <= '1'; -- Sets the red LED to ON. Not important for seedfinding.
		IF RISING_EDGE(SEED_CLK) THEN -- If the clock is on the rising edge, do the following.
			FOR I IN 0 TO instances - 1 LOOP -- Loop through 0 to instances - 1.
				start_inputs(I) <= start_inputs(I) + instance_adder; -- Increment every seed by the instance_adder.
			END LOOP;
			is_any_seed_valid <= valids(0) OR valids(1) OR valids(2) OR valids(3) OR valids(4) OR valids(5) OR valids(6) OR valids(7) OR valids(8) OR valids(9) OR valids(10) OR valids(11) OR valids(12) OR valids(13) OR valids(14) OR valids(15) OR valids(16) OR valids(17) OR valids(18) OR valids(19) OR valids(20) OR valids(21) OR valids(22) OR valids(23) OR valids(24) OR valids(25) OR valids(26) OR valids(27) OR valids(28) OR valids(29) OR valids(30) OR valids(31) OR valids(32) OR valids(33) OR valids(34) OR valids(35) OR valids(36) OR valids(37) OR valids(38) OR valids(39) OR valids(40) OR valids(41) OR valids(42) OR valids(43) OR valids(44) OR valids(45) OR valids(46) OR valids(47) OR valids(48) OR valids(49) OR valids(50) OR valids(51) OR valids(52) OR valids(53) OR valids(54) OR valids(55) OR valids(56) OR valids(57) OR valids(58) OR valids(59) OR valids(60) OR valids(61) OR valids(62) OR valids(63);
			-- Checks if ANY seed is valid. If one seed is valid, is_any_seed_valid will be valid aka 1.
			temp_seed_buffer  <= STD_LOGIC_VECTOR(start_inputs(0)); -- Set temp_seed_buffer to the first seed input. Most efficient way to send the seed to the UART FIFO.
			IF is_any_seed_valid = '1' THEN -- If any seed is valid then do the following.
				valid_seed  <= '1'; -- Set valid_seed to 1. This makes the UART FIFO write temp_seed_buffer and it will send it over UART.
				led_g_test <= NOT led_g_test; -- Not important to seedfinding.
			ELSE
				valid_seed <= '0'; -- Set valid_seed to 0. This needs to be set to 0 otherwise a bunch of seeds will be written to the UART FIFO and sent.
			END IF;
		END IF;
	END PROCESS;
	led_g <= led_g_test; -- Not important to seedfinding.
END arch;