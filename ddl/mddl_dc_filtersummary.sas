/**
  @file
  @brief Filtersummary DDL
  @details For storing summary filter values.  Used by
      mp_filterstore.sas.

**/


%macro mddl_dc_filtersummary(libds=WORK.FILTER_SUMMARY);

  proc sql;
  create table &libds(
      filter_rk num not null,
      filter_hash char(32) not null,
      filter_table char(41) not null,
      processed_dttm num not null format=E8601DT26.6,
    constraint pk_mpe_filteranytable
      primary key(filter_rk)
  );

%mend mddl_dc_filtersummary;