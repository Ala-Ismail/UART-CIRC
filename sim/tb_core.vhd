library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.tb_support_pkg.all;

entity tb_core is end entity;
architecture test of tb_core is
  signal clk : std_logic := '0';
  signal rst, tick : std_logic := '0';
  signal rx, settled : std_logic := '1';
  signal data_o : std_logic_vector(7 downto 0);
  signal valid_o, fe, be, active, busy : std_logic;
begin
  clock_75mhz(clk);
  dut : entity work.uart_rx_core port map(clk, rst, tick, rx, settled,
    data_o, valid_o, fe, be, active, busy);
  process
    variable expected_byte : std_logic_vector(7 downto 0);
    variable line_value, sample_value : std_logic;
    variable target : natural;
    procedure step(value : std_logic; enable : boolean := true; reset : boolean := false;
                   expected_valid : boolean := false; expected_fe : boolean := false;
                   expected_be : boolean := false) is
    begin
      wait until falling_edge(clk);
      rx<=value; tick<=bit_value(enable); rst<=bit_value(reset);
      wait until rising_edge(clk); wait for 1 ps;
      assert valid_o=bit_value(expected_valid) report "Core byte pulse" severity failure;
      assert fe=bit_value(expected_fe) report "Core framing pulse" severity failure;
      assert be=bit_value(expected_be) report "Core break pulse" severity failure;
      if expected_valid then assert data_o=expected_byte report "Core shift data" severity failure; end if;
    end;
    procedure initialize is
    begin step('1', reset=>true); step('1'); step('1'); end;
  begin
    initialize;
    -- Exhaust every byte with exactly numbered enables and intervening disabled clocks.
    for value in 0 to 255 loop
      expected_byte:=std_logic_vector(to_unsigned(value,8));
      step('0'); -- falling edge, not counted as enable one
      for sample in 1 to 152 loop
        if sample<=16 then rx<='0';
        elsif sample<=144 then rx<=expected_byte((sample-17)/16);
        else rx<='1'; end if;
        wait for 1 ps;
        if sample<=16 then
          step('0', false); step('0');
        elsif sample<=144 then
          step(expected_byte((sample-17)/16), false);
          step(expected_byte((sample-17)/16));
        else step('1', false); step('1', expected_valid=>sample=152);
        end if;
      end loop;
      step('1');
    end loop;
    -- False start goes back to idle at sample eight, without diagnostics.
    initialize; step('0');
    for i in 1 to 7 loop step('0'); end loop;
    step('1'); assert busy='0' report "False start recovery" severity failure;
    -- Glitches before/at/after each decision sample. Disabled-clock glitches
    -- are ignored; an enabled sample deliberately changes the decoded result.
    for decision in 0 to 9 loop
      if decision=0 then target:=8;
      elsif decision=9 then target:=152;
      else target:=24+(decision-1)*16; end if;
      for phase in 0 to 2 loop
        initialize;
        expected_byte:=x"AA";
        if phase=1 and decision>=1 and decision<=8 then
          expected_byte(decision-1):=not expected_byte(decision-1);
        end if;
        step('0',false);
        for sample in 1 to 152 loop
          if sample<=16 then line_value:='0';
          elsif sample<=144 then
            if ((sample-17)/16) mod 2=0 then line_value:='0'; else line_value:='1'; end if;
          else line_value:='1'; end if;
          if sample=target and phase=0 then step(not line_value,false); end if;
          sample_value:=line_value;
          if sample=target and phase=1 then sample_value:=not line_value; end if;
          step(sample_value,
            expected_valid=>sample=152 and not (phase=1 and (decision=0 or decision=9)),
            expected_fe=>sample=152 and phase=1 and decision=9);
          if sample=target and phase=2 then step(not line_value,false); end if;
        end loop;
      end loop;
    end loop;
    report "COVER GLITCH 10 decision points x before/at/after sampling; sample-dependent results checked";
    -- Low stop, qualified break, saturation, high recovery.
    initialize; step('0',false);
    for i in 1 to 159 loop step('0', expected_fe=>i=152); end loop;
    assert active='0' report "Early break" severity failure;
    step('0', expected_be=>true); assert active='1' severity failure;
    for i in 1 to 400 loop step('0'); end loop;
    step('1',false); assert active='0' and busy='0' severity failure;
    -- Reset in idle/start, each data sampling position, stop, and wait-high.
    for position in 0 to 153 loop
      initialize; step('0',false);
      for i in 1 to position loop step('0', expected_fe=>i=152); end loop;
      step('0', reset=>true);
      assert busy='0' and active='0' severity failure;
      for i in 1 to 5 loop step('0'); end loop; -- must remain unarmed
      assert busy='0' severity failure;
    end loop;
    -- Unsettled synchronizer high must not arm start detection.
    settled<='0'; step('1',reset=>true); step('1');
    settled<='1'; step('0',false);
    for i in 1 to 160 loop step('0',expected_be=>i=160); end loop;
    assert busy='0' and active='1' severity failure;
    report "COVER CORE all states/transitions, data bits, reset positions, break threshold";
    report "PASS tb_core";
    finish;
  end process;
  process begin wait for 5 ms; assert false report "Core timeout" severity failure; end process;
end architecture;
