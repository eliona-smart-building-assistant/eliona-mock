#!/bin/bash

# This file is part of the eliona project.
# Copyright © 2022 LEICOM iTEC AG. All Rights Reserved.
# ______ _ _
# |  ____| (_)
# | |__  | |_  ___  _ __   __ _
# |  __| | | |/ _ \| '_ \ / _` |
# | |____| | | (_) | | | | (_| |
# |______|_|_|\___/|_| |_|\__,_|
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
# BUT NOT LIMITED  TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NON INFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
# DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

cd /kafka || exit
/docker-entrypoint.sh start &

while : ; do
http_response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8083/connectors)
if [ "$http_response" -eq "200" ] ; then
break
fi
sleep 5
done

curl -i -X DELETE http://localhost:8083/connectors/eliona-connector
curl -i -X POST -H "Accept:application/json" -H "Content-Type:application/json" http://localhost:8083/connectors/ -d @/eliona-connector.json

sleep infinity