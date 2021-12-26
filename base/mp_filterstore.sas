/**
  @file
  @brief Checks & Stores an input filter table and returns the Filter Key
  @details Used to generate a FILTER_RK from an input query dataset.  This
  process requires several permanent tables (names are configurable):

  @li filterdetail (contains raw values)
  @li filtersummary (contains summary data about the filter)


  @param [in] libds= The target dataset to be filtered (lib should be assigned)
  @param [in] queryds= (WORK.FILTERQUERY) The temporary input query dataset to
    be validated.  Has the following format:
|GROUP_LOGIC:$3|SUBGROUP_LOGIC:$3|SUBGROUP_ID:8.|VARIABLE_NM:$32|OPERATOR_NM:$10|RAW_VALUE:$32767|
|---|---|---|---|---|---|
|AND|AND|1|SOME_BESTNUM|>|1|
|AND|AND|1|SOME_TIME|=|77333|
  @param [in] filter_summary= (PERM.FILTER_SUMMARY) Permanent table containing
    summary filter values. Structure:
|FILTER_RK:best.|FILTER_HASH:$32.|FILTER_TABLE:$41.|PROCESSED_DTTM:datetime19.|
|---|---|---|---|
|`1 `|`540E96F566D194AB58DD4C413C99C9DB `|`VIYA6014.MPE_TABLES `|`1956084246 `|
|`2 `|`87737DB9EEE2650F5C89956CEAD0A14F `|`VIYA6014.MPE_X_TEST `|`1956084452.1`|
|`3 `|`8048BD908DBBD83D013560734E90D394 `|`VIYA6014.MPE_TABLES `|`1956093620.6`|
  @param [in] filter_detail= (PERM.FILTER_DETAIL) Permanent table containing
    detailed (raw) filter values. Structure:
|FILTER_HASH:$32.|FILTER_LINE:best.|GROUP_LOGIC:$3.|SUBGROUP_LOGIC:$3.|SUBGROUP_ID:best.|VARIABLE_NM:$32.|OPERATOR_NM:$12.|RAW_VALUE:$4000.|PROCESSED_DTTM:datetime19.|
|---|---|---|---|---|---|---|---|---|
|`540E96F566D194AB58DD4C413C99C9DB `|`1 `|`AND `|`AND `|`1 `|`LIBREF `|`CONTAINS `|`DC`|`1956084245.8 `|
|`540E96F566D194AB58DD4C413C99C9DB `|`2 `|`AND `|`OR `|`2 `|`DSN `|`= `|` MPE_LOCK_ANYTABLE `|`1956084245.8 `|
|`87737DB9EEE2650F5C89956CEAD0A14F `|`1 `|`AND `|`AND `|`1 `|`PRIMARY_KEY_FIELD `|`IN `|`(1,2,3) `|`1956084451.9 `|
  @param [in] lock_table= (PERM.LOCK_TABLE) Permanent locking table.  Used to
    manage concurrent access.  Described in mp_lockanytable.sas.
  @param [in] maxkeytable= (0) Optional permanent reference table used for
    retained key tracking.  Described in mp_retainedkey.sas.
  @param [in] mdebug= set to 1 to enable DEBUG messages
  @param [out] outresult= The result table with the FILTER_RK
  @param [out] outquery= The original query, taken as extract after table load


  <h4> SAS Macros </h4>
  @li mf_getuniquename.sas
  @li mf_getvalue.sas
  @li mf_islibds.sas
  @li mf_nobs.sas
  @li mp_abort.sas
  @li mp_filtercheck.sas
  @li mp_hashdataset.sas
  @li mp_retainedkey.sas

  <h4> Related Macros </h4>
  @li mp_filtercheck.sas
  @li mp_filtergenerate.sas
  @li mp_filtervalidate.sas
  @li mp_filterstore.test.sas

  @version 9.2
  @author [Allan Bowe](https://www.linkedin.com/in/allanbowe)

**/

%macro mp_filterstore(libds=,
  queryds=work.filterquery,
  filter_summary=PERM.FILTER_SUMMARY,
  filter_detail=PERM.FILTER_DETAIL,
  lock_table=PERM.LOCK_TABLE,
  maxkeytable=PERM.MAXKEYTABLE,
  outresult=work.result,
  outquery=work.query,
  mdebug=1
);
%put &sysmacroname entry vars:;
%put _local_;

%local ds1 ds2 ds3 ds4 filter_hash;
%mp_abort(iftrue= (&syscc ne 0)
  ,mac=mp_filterstore
  ,msg=%str(syscc=&syscc on macro entry)
)
%mp_abort(iftrue= (%mf_islibds(&filter_summary)=0)
  ,mac=mp_filterstore
  ,msg=%str(Invalid filter_summary value: &filter_summary)
)
%mp_abort(iftrue= (%mf_islibds(&filter_detail)=0)
  ,mac=mp_filterstore
  ,msg=%str(Invalid filter_detail value: &filter_detail)
)
%mp_abort(iftrue= (%mf_islibds(&lock_table)=0)
  ,mac=mp_filterstore
  ,msg=%str(Invalid lock_table value: &lock_table)
)

/* validate query */
%mp_filtercheck(&queryds,targetds=&libds,abort=YES)

/* hash the result */
%mp_hashdataset(&queryds,outds=&ds1,salt=&libds)
%let filter_hash=%upcase(%mf_getvalue(&ds1,hashkey));
%if &mdebug=1 %then %do;
  data _null_;
    putlog "filter_hash=&filter_hash";
    set &ds1;
    putlog (_all_)(=);
  run;
%end;

/* check if data already exists for this hash */
data &outresult;
  set &filter_summary;
  where filter_hash="&filter_hash";
run;

%mp_abort(iftrue= (&syscc ne 0)
  ,mac=mp_filterstore
  ,msg=%str(syscc=&syscc after hash check)
)
%mp_abort(iftrue= ("&filter_hash"=" ")
  ,mac=mp_filterstore
  ,msg=%str(problem with filter_hash generation)
)

%if %mf_nobs(&outresult)=0 %then %do;

  /* update detail table first */
  %let ds2=%mf_getuniquename(prefix=filterdetail);
  data &ds2;
    set &queryds;
    format filter_hash $hex32. filter_line 8. processed_dttm E8601DT26.6;
    filter_hash="&filter_hash";
    filter_line=_n_;
    PROCESSED_DTTM="%sysfunc(datetime(),E8601DT26.6)"dt;
  run;
  %mp_lockanytable(LOCK,
    lib=%scan(&filter_detail,1,.)
    ,ds=%scan(&filter_detail,2,.)
    ,ref=MP_FILTERSTORE update - &filter_hash
    ,ctl_ds=&lock_table
  )
  proc append base=&filter_detail data=&ds2;
  run;

  %mp_lockanytable(UNLOCK,
    lib=%scan(&filter_detail,1,.)
    ,ds=%scan(&filter_detail,2,.)
    ,ref=MP_FILTERSTORE update - &filter_hash
    ,ctl_ds=&lock_table
  )

  /* now update summary table */
  %let ds3=%mf_getuniquename(prefix=filtersum);
  data &ds3;
    if 0 then set &filter_summary;
    filter_table=symget('libds');
    filter_hash="&filter_hash";
    PROCESSED_DTTM="%sysfunc(datetime(),E8601DT26.6)"dt;
    output;
    stop;
  run;

  %mp_lockanytable(LOCK,
    lib=%scan(&filter_summary,1,.)
    ,ds=%scan(&filter_summary,2,.)
    ,ref=MP_FILTERSTORE update - &filter_hash
    ,ctl_ds=&lock_table
  )

  %let ds4=%mf_getuniquename(prefix=filtersumappend);
  %mp_retainedkey(
    base_lib=%scan(&filter_summary,1,.)
    ,base_dsn=%scan(&filter_summary,2,.)
    ,append_lib=%scan(&ds3,1,.)
    ,append_dsn=%scan(&ds3,2,.)
    ,retained_key=filter_rk
    ,business_key=filter_hash
    ,maxkeytable=&maxkeytable
    ,locktable=&lock_table
    ,outds=&ds4
  )
  proc append base=&filter_summary data=&ds4;
  run;

  %mp_lockanytable(UNLOCK,
    lib=%scan(&filter_summary,1,.)
    ,ds=%scan(&filter_summary,2,.)
    ,ref=MP_FILTERSTORE update - &filter_hash
    ,ctl_ds=&lock_table
  )

  data &outresult;
    set &filter_summary;
    where filter_hash="&filter_hash";
  run;

%end;

proc sort data=&filter_detail(where=(filter_hash="&filter_hash")) out=&outquery;
  by filter_line;
run;

%mp_abort(iftrue= (&syscc ne 0)
  ,mac=mp_filterstore
  ,msg=%str(syscc=&syscc on macro exit)
)

%mend mp_filterstore;