CREATE OR REPLACE FUNCTION getFeriadosMoveis (IN ANO numeric(4) DEFAULT date_part('year', NOW()), OUT DataFeriado DATE, OUT DiaSemana TEXT, OUT Comemoracao TEXT)
RETURNS SETOF RECORD AS $$
 DECLARE
-- Retorna a data da Pascoa (getDataPascoa (ANO numeric(4) DEFAULT date_part('year', NOW())))
-- @author Pedro Junior <v.ju.ni.or.v@gmail.com>
-- @param ANO integer
-- @return Date
-- Modificado por Eder Sousa (11/02/2013)

/*
Demais feriados móveis
Domingo de Carnaval P - 49 dias
Terça-feira de Carnaval P - 47 dias
Quarta-feira de Cinzas P - 46 dias
Domingo de Ramos P - 7 dias
Sexta-feira da Paixão P - 2 dias
Corpus Christi         P + 60 dias
*/
  DIA numeric(2); -- Dia do Natal
  MES     numeric(2); -- Mês do Natal
 
  X numeric(2); -- Valor de X de acordo com a faixa de anos
  Y numeric(2); -- Valor de Y de acordo com a faixa de anos
 
  aM numeric(2); -- Valor para MOD de A
  bM numeric(2); -- Valor para MOD de B
  cM numeric(2); -- Valor para MOD de C
  dM numeric(2); -- Valor para MOD de D
 
  A numeric(2); -- Ano MOD aM
  B numeric(2); -- Ano MOD bM
  C numeric(2); -- Ano MOD cM
  D numeric(2); -- (aM * A + X) MOD dM
  E numeric(2); -- (2 * B + bM * C + 6 * D + Y) MOD cM
 
  DeE  numeric(2); -- (D + E)
  r    RECORD;
  txtDiaSemana TEXT;
  DATA date; -- Data da Pascoa Calculada
 BEGIN
  Create temp table x (DtFeriado DATE, DiaSemana Text, Comemoracao TEXT);
  
  X = 
   CASE
    WHEN ANO BETWEEN 1582 AND 1699 THEN 22
    WHEN ANO BETWEEN 1700 AND 1799 THEN 23
    WHEN ANO BETWEEN 1800 AND 2199 THEN 24
    WHEN ANO BETWEEN 2200 AND 2299 THEN 25
   END;
  Y = 
   CASE
    WHEN ANO BETWEEN 1582 AND 1699 THEN 2
    WHEN ANO BETWEEN 1700 AND 1799 THEN 3
    WHEN ANO BETWEEN 1800 AND 1899 THEN 4
    WHEN ANO BETWEEN 1900 AND 2099 THEN 5
    WHEN ANO BETWEEN 2100 AND 2199 THEN 6
    WHEN ANO BETWEEN 2200 AND 2299 THEN 7
   END;
  aM = 19;
  bM = 4;
  cM = 7;
  dM = 30;
 
  A = mod(ANO, aM);
  B = mod(ANO, bM);
  C = mod(ANO, cM);
  D = mod((aM * A + X), dM);
  E = mod((2 * B + bM * C + 6 * D + Y), cM); 
  DeE = D + E;
 
  IF (DeE > 9) THEN
   DIA = DeE - 9;
   MES = 4;
    
   -- Casos que só ocorrem duas vezes por século: -- Se o Dia for 26 então corrige para uma semana antes
   IF (DIA = 26) THEN DIA = DIA - cM; END IF;
 
   -- Se o Dia for 25 e D for 28 e A > 10 então corrige o dia pra 18
   IF (DIA = 25 AND D = 28 AND A > 10) THEN DIA = 18; END IF;   
  ELSE
   DIA = DeE + 22;
   MES = 3;  
  END IF;

  DATA = to_date(DIA || '/' || MES || '/' || ANO, 'DD-MM-YYYY');
  Insert into x (DtFeriado, Comemoracao) values (DATA, 'Páscoa'),
                (DATA-'49 Days'::interval,'Domingo de carnaval'),
                (DATA-'47 Days'::interval,'Terça-feria de carnaval'),
                (DATA-'46 Days'::interval,'Quarta-feria de cinzas'),
                (DATA-'7 Days'::interval,'Domingo de ramos'),
                (DATA-'2 Days'::interval,'Sexta-feira da paixão'),
                (DATA+'60 Days'::interval,'Corpus Christi'),
                (to_date('25/12/' || ANO, 'DD-MM-YYYY'),'Natal'),
                (to_date('15/11/' || ANO, 'DD-MM-YYYY'),'Proclamação da república'),
                (to_date('02/11/' || ANO, 'DD-MM-YYYY'),'Finados'),
                (to_date('21/04/' || ANO, 'DD-MM-YYYY'),'Tiradentes'),
                (to_date('01/05/' || ANO, 'DD-MM-YYYY'),'Dia do trabalhador'),
                (to_date('01/01/' || ANO, 'DD-MM-YYYY'),'Confraternização universal'),
                (to_date('12/10/' || ANO, 'DD-MM-YYYY'),'Nossa Sra Aparecida'),
                (to_date('07/09/' || ANO, 'DD-MM-YYYY'),'Independência do Brasil');
   Update x set DiaSemana = DiaDaSemana(DtFeriado);
   Return query select x.DtFeriado, x.DiaSemana, x.Comemoracao from x order by DtFeriado asc;
   drop table x;
 END
$$ LANGUAGE 'PLPGSQL';

--select * from getFeriadosMoveis(2013);