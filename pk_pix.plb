create or replace package body pkg_pix as
  /*
    Created by Vinicius Damarques
    https://github.com/vihdamarques/plsql-pix/
  */

  type t_nested_tlv is table of varchar2(32767) index by varchar2(2);
  --
  C_ID_PAYLOAD_FORMAT_INDICATOR                 constant varchar2(2)  := '00';
  C_ID_MERCHANT_ACCOUNT_INFORMATION             constant varchar2(2)  := '26';
  C_ID_MERCHANT_ACCOUNT_INFORMATION_GUI         constant varchar2(2)  := '00';
  C_ID_MERCHANT_ACCOUNT_INFORMATION_KEY         constant varchar2(2)  := '01';
  C_ID_MERCHANT_ACCOUNT_INFORMATION_DESCRIPTION constant varchar2(2)  := '02';
  C_ID_MERCHANT_CATEGORY_CODE                   constant varchar2(2)  := '52';
  C_ID_TRANSACTION_CURRENCY                     constant varchar2(2)  := '53';
  C_ID_TRANSACTION_AMOUNT                       constant varchar2(2)  := '54';
  C_ID_COUNTRY_CODE                             constant varchar2(2)  := '58';
  C_ID_MERCHANT_NAME                            constant varchar2(2)  := '59';
  C_ID_MERCHANT_CITY                            constant varchar2(2)  := '60';
  C_ID_ADDITIONAL_DATA_FIELD_TEMPLATE           constant varchar2(2)  := '62';
  C_ID_ADDITIONAL_DATA_FIELD_TEMPLATE_TXID      constant varchar2(2)  := '05';
  C_ID_CRC16                                    constant varchar2(2)  := '63';
  C_PAYLOAD_FORMAT_INDICATOR                    constant varchar2(2)  := '01';
  C_GUI                                         constant varchar2(14) := 'BR.GOV.BCB.PIX';
  C_MERCHANT_CATEGORY_CODE                      constant varchar2(4)  := '0000'; -- Not informed or MCC ISO18245
  C_TRANSACTION_CURRENCY                        constant varchar2(3)  := '986'; -- ISO4217 (BRL)
  C_COUNTRY_CODE                                constant varchar2(2)  := 'BR'; -- ISO3166-1 alpha 2

  function get_crc16(p_input varchar2) return varchar2 is
    l_xFFFF      constant number := to_number('FFFF', 'XXXX');
    l_x1021      constant number := to_number('1021', 'XXXX');
    l_crc        number := l_xFFFF; -- Valor inicial (0xFFFF)
    l_polynomial number := l_x1021; -- Polinômio 0x1021
    l_byte_value number;
    l_bit_mask   number;
  begin
    for i in 1 .. length(p_input) loop
      l_byte_value := ascii(substr(p_input, i, 1));
      l_crc := bitand(l_crc, l_xFFFF) + (l_byte_value * 256) - 2 * bitand(l_crc, l_byte_value * 256);

      for j in 1 .. 8 loop
        l_bit_mask := bitand(l_crc, 32768); -- Verifica o bit mais significativo
        l_crc := mod(l_crc * 2, to_number('10000', 'XXXXX')); -- Simula um shift left (SHL)
        if l_bit_mask <> 0 then
          l_crc := bitand(l_crc, l_xFFFF) + l_polynomial - 2 * bitand(l_crc, l_polynomial);
        end if;
      end loop;
    end loop;

    return to_char(l_crc, 'fmXXXXXXXX');
  end get_crc16;

  function get_tlv(p_type in varchar2, p_value in varchar2) return varchar2 is -- TLV = type, length, value
  begin
    return p_type || lpad(length(p_value), 2, '0') || p_value;
  end get_tlv;

  function get_nested_tlv(p_type in varchar2, p_value in t_nested_tlv) return varchar2 is
    l_child_type varchar2(2);
    l_tlv        varchar2(32767);
  begin
    l_child_type := p_value.first;
    loop
      exit when l_child_type is null;

      l_tlv := l_tlv || get_tlv(p_type => l_child_type, p_value => p_value(l_child_type));

      l_child_type := p_value.next(l_child_type);
    end loop;

    return get_tlv(p_type => p_type, p_value => l_tlv);
  end get_nested_tlv;

  function is_key_valid(p_key in varchar2) return boolean is
  begin
    return regexp_like(p_key, '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') -- email
        or regexp_like(p_key, '^\+[1-9]\d{1,14}$') -- phone
        or regexp_like(p_key, '^\d{11}(\d{3})?$') -- CPF/CNPJ
        or regexp_like(p_key, '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'); -- EVP (Random)
  end is_key_valid;

  function get_static_brcode(p_key           in varchar2,
                             p_merchant_name in varchar2,
                             p_merchant_city in varchar2,
                             p_txid          in varchar2,
                             p_amount        in number   default null,
                             p_description   in varchar2 default null) return varchar2 is
    l_pix                          varchar2(32767);
    l_amount                       number       := trunc(p_amount, 2);
    l_merchant_name                varchar2(25) := substr(p_merchant_name, 1, 25);
    l_merchant_city                varchar2(25) := substr(p_merchant_city, 1, 25);
    l_merchant_account_information t_nested_tlv;
    l_additional_data              t_nested_tlv;
  begin
    if not is_key_valid(p_key) then
      raise_application_error(-20001, 'Invalid Key');
    end if;

    if length(p_description) > 35 then
      raise_application_error(-20001, 'Max description length is 35 characters');
    end if;

    if length(p_txid) > 25 then
      raise_application_error(-20001, 'Max TXID length is 25 characters');
    end if;

    -- 00
    l_pix := get_tlv(p_type => C_ID_PAYLOAD_FORMAT_INDICATOR, p_value => C_PAYLOAD_FORMAT_INDICATOR);
    -- 26
    l_merchant_account_information(C_ID_MERCHANT_ACCOUNT_INFORMATION_GUI) := C_GUI;
    l_merchant_account_information(C_ID_MERCHANT_ACCOUNT_INFORMATION_KEY) := p_key;
    if p_description is not null then
      l_merchant_account_information(C_ID_MERCHANT_ACCOUNT_INFORMATION_DESCRIPTION) := p_description;
    end if;
    l_pix := l_pix || get_nested_tlv(p_type => C_ID_MERCHANT_ACCOUNT_INFORMATION, p_value => l_merchant_account_information);
    -- 52
    l_pix := l_pix || get_tlv(p_type => C_ID_MERCHANT_CATEGORY_CODE, p_value => C_MERCHANT_CATEGORY_CODE);
    -- 53
    l_pix := l_pix || get_tlv(p_type => C_ID_TRANSACTION_CURRENCY, p_value => C_TRANSACTION_CURRENCY);
    -- 54
    if p_amount is not null then
      l_pix := l_pix || get_tlv(p_type => C_ID_TRANSACTION_AMOUNT, p_value => to_char(l_amount, 'fm999g999g999g999g990d00', 'nls_numeric_characters=''.,'''));
    end if;
    -- 58
    l_pix := l_pix || get_tlv(p_type => C_ID_COUNTRY_CODE, p_value => C_COUNTRY_CODE);
    -- 59
    l_pix := l_pix || get_tlv(p_type => C_ID_MERCHANT_NAME, p_value => l_merchant_name);
    -- 60
    l_pix := l_pix || get_tlv(p_type => C_ID_MERCHANT_CITY, p_value => l_merchant_city);
    -- 62
    l_additional_data(C_ID_ADDITIONAL_DATA_FIELD_TEMPLATE_TXID) := p_txid;
    l_pix := l_pix || get_nested_tlv(p_type => C_ID_ADDITIONAL_DATA_FIELD_TEMPLATE, p_value => l_additional_data);
    -- 63
    l_pix := l_pix || get_tlv(p_type => C_ID_CRC16, p_value => get_crc16(l_pix || C_ID_CRC16 || '04')); -- 04 default size of CRC-16 output

    return l_pix;
  end get_static_brcode;

end pkg_pix;
/
