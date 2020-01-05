# pgconfgen
Wait for trigger, update local files, reload, repeat.



## Example use case: 
### Generate configuration file for PowerDNS recursor

**Problem to solve**: PDNS Recursor forwards queries to authoritative PDNS daemon. Recursor does not support database backend and usually you have to tell it in the config file which domains it should forward using the `forward-zones` entry. You have to manually edit `recursor.conf` even thou this information is already present in the database backend.

**Solution**: Point `pgconfgen` to the powerdns database and let it watch for changes in `domains` table. As soon as the change is detected, regenerate the config file and call `rec_control reload-zones`.

**Bonus objective**: create two more tables: `cfg_pdns` and `cfg_recursor` which can be used to remotely configure any PowerDNS configuration parameters without touching the actual server. Very handy in cooperation with some administration backend that can do a GUI for you.

**Note**: For detecting changes promptly, you have to execute `select pg_notify(...);` after every change. You can do it as a post-save hook in your interface or you can create a DB trigger that will do it for you.

Sample `/etc/pgconfgen/pgconfgen.ini`:
```
[main]
db_connstring = host=10.10.10.10 port=6432 user=pdns password=VerySecretPass dbname=pdns connect_timeout=3
db_retry_timeout=30
db_keepalive=900
notify_channel= pdns_notify

[domains_modified]
jinja_template = /root/pdns-configd/forward-zones.conf.j2
outfile  = /etc/recursor.conf.d/forward-zones.conf
reload_command = /opt/local/bin/rec_control reload-zones | grep -vq failed
table_name = domains
table_cols =name

[recursor_cfg_modified]
jinja_template = /etc/pgconfgen/generic.conf.j2
outfile  = /etc/recursor.conf.d/extra.conf
reload_command = /usr/local/bin/rec_control reload-zones | grep -vq failed
table_name = cfg_recursor
table_cols = key, val

[pdns_cfg_modified]
jinja_template = /etc/pgconfgen/generic.conf.j2
outfile  = /etc/pdns.conf.d/extra.conf
reload_command = /usr/local/bin/rec_control reload-zones | grep -vq failed
table_name = cfg_pdns
table_cols = key, value
```
As you can see, we will not touch the main config files, we will only add auxiliary config file `extra.conf`. That allows us to start with an empty SQL config tables. But make sure you include the extra dir from the main conf files: `include-dir=/etc/recursor.conf.d`.

#### Add trigger to domains table
```
create or replace function public.pdns_domains_notify() returns trigger as $BODY$
begin
perform pg_notify('pdns_notify', 'domains_modified');
return new;
end;
$BODY$
language 'plpgsql' volatile cost 100;

create trigger pdns_domains_changed after insert or update or delete on public.domains execute procedure public.pdns_domains_notify();
```

#### Bonus objective: Create the pdns config database tables
If you don't want a bonus objective, skip to the next section. Create tables
```
    CREATE TABLE cfg_pdns (
        key             VARCHAR(32) NOT NULL PRIMARY KEY,
        val             TEXT DEFAULT NULL,
        change_date     INT DEFAULT NULL,
    );
    CREATE UNIQUE INDEX cfg_pdns_index ON cfg_pdns(key);
    
    CREATE TABLE cfg_recursor (
        key             VARCHAR(32) NOT NULL PRIMARY KEY,
        val             TEXT DEFAULT NULL,
        change_date     INT DEFAULT NULL,

    );
    CREATE UNIQUE INDEX cfg_recursor_index ON cfg_recursor(key);
```
Add triggers:
```
create or replace function public.pdns_cfg_notify() returns trigger as $BODY$
begin
perform pg_notify('pdns_notify', 'pdns_cfg_modified');
return new;
end;
$BODY$
language 'plpgsql' volatile cost 100;

create trigger pdns_cfg_changed after insert or update or delete on public.cfg_pdns execute procedure public.pdns_cfg_notify();

create or replace function public.pdns_recursor_cfg_notify() returns trigger as $BODY$
begin
perform pg_notify('pdns_notify', 'pdns_cfg_modified');
return new;
end;
$BODY$
language 'plpgsql' volatile cost 100;

create trigger pdns_recursor_cfg_changed after insert or update or delete on public.cfg_recursor execute procedure public.pdns_recursor_cfg_notify();
```
### Start the daemon
For initial test run, start in a debug mode:
```
./pgconfgen -c /etc/pgconfgen/pgconfgen.ini -d
```
In production you can omit `-d`. It logs to the stdout so it is suitable for running under systemd.
