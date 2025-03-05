#!/bin/bash

steampipe service start

# TODO RUN THIS TO PROTECT THE DB
# GRANT SELECT ON public_data1, public_data2 TO steampipe_user;
# REVOKE ALL ON ALL TABLES IN SCHEMA public FROM steampipe_user;
# GRANT SELECT ON public_data1, public_data2 TO steampipe_user;

# Keep the container alive with noop
exec tail -f /dev/null
