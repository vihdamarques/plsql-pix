# plsql-pix

PL/SQL library to generate Brazil's instant payment code called PIX.

## Features

For now, only static pix is supported.

## Example

      select pkg_pix.get_static_brcode(p_key           => 'email@domain.com',
                                       p_description   => 'pix description',
                                       p_merchant_name => 'John Doe',
                                       p_merchant_city => 'SAO PAULO',
                                       p_txid          => 'transaction_id_123',
                                       p_amount        => 1.23) as pix
        from dual;
