/**
  @file mm_webout.sas
  @brief Send data to/from SAS Stored Processes
  @details This macro should be added to the start of each Stored Process,
  **immediately** followed by a call to:

        %mm_webout(FETCH)

    This will read all the input data and create same-named SAS datasets in the
    WORK library.  You can then insert your code, and send data back using the
    following syntax:

        data some datasets; * make some data ;
        retain some columns;
        run;

        %mm_webout(OPEN)
        %mm_webout(ARR,some)  * Array format, fast, suitable for large tables ;
        %mm_webout(OBJ,datasets) * Object format, easier to work with ;

    Finally, wrap everything up send some helpful system variables too

        %mm_webout(CLOSE)


  @param [in] action Either FETCH, OPEN, ARR, OBJ or CLOSE
  @param [in] ds The dataset to send back to the frontend
  @param [out] dslabel= Value to use instead of table name for sending to JSON
  @param [in] fmt=(Y) Set to N to send back unformatted values
  @param [out] fref= (_webout) The fileref to which to write the JSON
  @param [in] missing= (NULL) Special numeric missing values can be sent as NULL
    (eg `null`) or as STRING values (eg `".a"` or `".b"`)
  @param [in] showmeta= (NO) Set to YES to output metadata alongside each table,
    such as the column formats and types.  The metadata is contained inside an
    object with the same name as the table but prefixed with a dollar sign - ie,
    `,"$tablename":{"formats":{"col1":"$CHAR1"},"types":{"COL1":"C"}}`

  @version 9.3
  @author Allan Bowe

**/
%macro mm_webout(action,ds,dslabel=,fref=_webout,fmt=Y,missing=NULL
  ,showmeta=NO
);
%global _webin_file_count _webin_fileref1 _webin_name1 _program _debug
  sasjs_tables;
%local i tempds jsonengine;

/* see https://github.com/sasjs/core/issues/41 */
%if "%upcase(&SYSENCODING)" ne "UTF-8" %then %let jsonengine=PROCJSON;
%else %let jsonengine=DATASTEP;


%if &action=FETCH %then %do;
  %if %str(&_debug) ge 131 %then %do;
    options mprint notes mprintnest;
  %end;
  %let _webin_file_count=%eval(&_webin_file_count+0);
  /* now read in the data */
  %do i=1 %to &_webin_file_count;
    %if &_webin_file_count=1 %then %do;
      %let _webin_fileref1=&_webin_fileref;
      %let _webin_name1=&_webin_name;
    %end;
    data _null_;
      infile &&_webin_fileref&i termstr=crlf;
      input;
      call symputx('input_statement',_infile_);
      putlog "&&_webin_name&i input statement: "  _infile_;
      stop;
    data &&_webin_name&i;
      infile &&_webin_fileref&i firstobs=2 dsd termstr=crlf encoding='utf-8';
      input &input_statement;
      %if %str(&_debug) ge 131 %then %do;
        if _n_<20 then putlog _infile_;
      %end;
    run;
    %let sasjs_tables=&sasjs_tables &&_webin_name&i;
  %end;
%end;

%else %if &action=OPEN %then %do;
  /* fix encoding */
  OPTIONS NOBOMFILE;

  /**
    * check xengine type to avoid the below err message:
    * > Function is only valid for filerefs using the CACHE access method.
    */
  data _null_;
    set sashelp.vextfl(where=(fileref="_WEBOUT"));
    if xengine='STREAM' then do;
      rc=stpsrv_header('Content-type',"text/html; encoding=utf-8");
    end;
  run;

  /* setup json */
  data _null_;file &fref encoding='utf-8';
  %if %str(&_debug) ge 131 %then %do;
    put '>>weboutBEGIN<<';
  %end;
    put '{"SYSDATE" : "' "&SYSDATE" '"';
    put ',"SYSTIME" : "' "&SYSTIME" '"';
  run;

%end;

%else %if &action=ARR or &action=OBJ %then %do;
  %mp_jsonout(&action,&ds,dslabel=&dslabel,fmt=&fmt,jref=&fref
    ,engine=&jsonengine,missing=&missing,showmeta=&showmeta
  )
%end;
%else %if &action=CLOSE %then %do;
  %if %str(&_debug) ge 131 %then %do;
    /* if debug mode, send back first 10 records of each work table also */
    options obs=10;
    data;run;%let tempds=%scan(&syslast,2,.);
    ods output Members=&tempds;
    proc datasets library=WORK memtype=data;
    %local wtcnt;%let wtcnt=0;
    data _null_;
      set &tempds;
      if not (upcase(name) =:"DATA"); /* ignore temp datasets */
      i+1;
      call symputx(cats('wt',i),name,'l');
      call symputx('wtcnt',i,'l');
    data _null_; file &fref mod encoding='utf-8';
      put ",""WORK"":{";
    %do i=1 %to &wtcnt;
      %let wt=&&wt&i;
      data _null_; file &fref mod encoding='utf-8';
        dsid=open("WORK.&wt",'is');
        nlobs=attrn(dsid,'NLOBS');
        nvars=attrn(dsid,'NVARS');
        rc=close(dsid);
        if &i>1 then put ','@;
        put " ""&wt"" : {";
        put '"nlobs":' nlobs;
        put ',"nvars":' nvars;
      %mp_jsonout(OBJ,&wt,jref=&fref,dslabel=first10rows,showmeta=YES)
      data _null_; file &fref mod encoding='utf-8';
        put "}";
    %end;
    data _null_; file &fref mod encoding='utf-8';
      put "}";
    run;
  %end;
  /* close off json */
  data _null_;file &fref mod encoding='utf-8';
    _PROGRAM=quote(trim(resolve(symget('_PROGRAM'))));
    put ",""SYSUSERID"" : ""&sysuserid"" ";
    put ",""MF_GETUSER"" : ""%mf_getuser()"" ";
    put ",""_DEBUG"" : ""&_debug"" ";
    _METAUSER=quote(trim(symget('_METAUSER')));
    put ",""_METAUSER"": " _METAUSER;
    _METAPERSON=quote(trim(symget('_METAPERSON')));
    put ',"_METAPERSON": ' _METAPERSON;
    put ',"_PROGRAM" : ' _PROGRAM ;
    put ",""SYSCC"" : ""&syscc"" ";
    syserrortext=quote(cats(symget('SYSERRORTEXT')));
    put ',"SYSERRORTEXT" : ' syserrortext;
    put ",""SYSHOSTNAME"" : ""&syshostname"" ";
    put ",""SYSJOBID"" : ""&sysjobid"" ";
    put ",""SYSSCPL"" : ""&sysscpl"" ";
    put ",""SYSSITE"" : ""&syssite"" ";
    sysvlong=quote(trim(symget('sysvlong')));
    put ',"SYSVLONG" : ' sysvlong;
    syswarningtext=quote(cats(symget('SYSWARNINGTEXT')));
    put ',"SYSWARNINGTEXT" : ' syswarningtext;
    put ',"END_DTTM" : "' "%sysfunc(datetime(),E8601DT26.6)" '" ';
    length memsize $32;
    memsize="%sysfunc(INPUTN(%sysfunc(getoption(memsize)), best.),sizekmg.)";
    memsize=quote(cats(memsize));
    put ',"MEMSIZE" : ' memsize;
    put "}" @;
  %if %str(&_debug) ge 131 %then %do;
    put '>>weboutEND<<';
  %end;
  run;
%end;

%mend mm_webout;
