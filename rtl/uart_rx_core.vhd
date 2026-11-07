library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uart_rx_core is
  port (clk, rst, sample_tick, rx_sync, settled : in std_logic;
        byte_data : out std_logic_vector(7 downto 0);
        byte_valid, framing_event, break_event, break_active, rx_busy : out std_logic);
end entity;

architecture rtl of uart_rx_core is
  type state_t is (IDLE, START_BIT, DATA_BITS, STOP_BIT, WAIT_HIGH);
  signal state : state_t := IDLE;
  signal armed : std_logic := '0';
  signal previous_rx : std_logic := '1';
  signal bit_timer : unsigned(3 downto 0) := (others => '0');
  signal bit_index : natural range 0 to 7 := 0;
  signal shift_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal low_count : unsigned(7 downto 0) := (others => '0');
  signal break_active_reg : std_logic := '0';
begin
  break_active <= break_active_reg;
  rx_busy <= '1' when state = START_BIT or state = DATA_BITS or state = STOP_BIT else '0';
  process(clk)
  begin
    if rising_edge(clk) then
      byte_valid <= '0';
      framing_event <= '0';
      break_event <= '0';
      if rst = '1' then
        state <= IDLE;
        armed <= '0';
        previous_rx <= '1';
        bit_timer <= (others => '0');
        bit_index <= 0;
        shift_reg <= (others => '0');
        byte_data <= (others => '0');
        low_count <= (others => '0');
        break_active_reg <= '0';
      else
        previous_rx <= rx_sync;
        if settled = '1' and rx_sync = '1' then armed <= '1'; end if;
        if settled = '0' or rx_sync = '1' then
          low_count <= (others => '0');
          break_active_reg <= '0';
        elsif sample_tick = '1' and break_active_reg = '0' then
          low_count <= low_count + 1;
          if low_count(7 downto 4) = 9 and low_count(3 downto 0) = 15 then
            break_active_reg <= '1';
            break_event <= '1';
          end if;
        end if;

        case state is
          when IDLE =>
            if armed = '1' and previous_rx = '1' and rx_sync = '0' then
              bit_timer <= to_unsigned(7, bit_timer'length);
              state <= START_BIT;
            end if;
          when START_BIT =>
            if sample_tick = '1' then
              bit_timer <= bit_timer - 1;
              if bit_timer = 0 then
                bit_timer <= (others => '1');
                if rx_sync = '0' then
                  state <= DATA_BITS;
                  bit_index <= 0;
                else state <= IDLE;
                end if;
              end if;
            end if;
          when DATA_BITS =>
            if sample_tick = '1' then
              bit_timer <= bit_timer - 1;
              if bit_timer = 0 then
                -- Reload by modulo-16 subtraction; fixed shift wiring avoids
                -- dynamically indexed write enables on the eight data flops.
                shift_reg <= rx_sync & shift_reg(7 downto 1);
                if bit_index = 7 then state <= STOP_BIT;
                else bit_index <= bit_index + 1;
                end if;
              end if;
            end if;
          when STOP_BIT =>
            if sample_tick = '1' then
              bit_timer <= bit_timer - 1;
              if bit_timer = 0 then
                if rx_sync = '1' then
                  byte_data <= shift_reg;
                  byte_valid <= '1';
                  state <= IDLE;
                else
                  framing_event <= '1';
                  state <= WAIT_HIGH;
                end if;
              end if;
            end if;
          when WAIT_HIGH =>
            if rx_sync = '1' then state <= IDLE; end if;
        end case;
      end if;
    end if;
  end process;
end architecture;
