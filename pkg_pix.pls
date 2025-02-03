create or replace package pkg_pix as
  function get_static_brcode(p_key           in varchar2,
                             p_merchant_name in varchar2,
                             p_merchant_city in varchar2,
                             p_txid          in varchar2,
                             p_amount        in number   default null,
                             p_description   in varchar2 default null) return varchar2;
end pkg_pix;
/
