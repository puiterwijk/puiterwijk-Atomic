#!/bin/bash
curl -i -X POST --header "x-api-key: $TRIGGER_API_KEY" https://5hpbtz3pd0.execute-api.eu-west-1.amazonaws.com/prod/TriggerBuild
