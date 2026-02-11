# D-036 L3 verification (post rule-load params wiring)

- started_utc=2026-02-11T14:33:21Z
- poll_seconds=30
- timeout_seconds=900
- run_id=l3_d036_param_20260211T143321Z
- job_id.sync=266854261681287
- job_id.setup=920043826442932
- job_id.e2e_full=1014961373700837
- start_ts=2026-02-11T12:33:21Z
- end_ts=2026-02-11T14:33:21Z

## Run log
\n### sync_dim_rule_scd2
job_parameters={"seed_path":"mock_data/fixtures/dim_rule_scd2.json","table_name":"gold.dim_rule_scd2"}
{
  "cleanup_duration":0,
  "creator_user_name":"2dt026@msacademy.msai.kr",
  "end_time":1770820584605,
  "execution_duration":82000,
  "job_clusters": [
    {
      "job_cluster_key":"policy_single_node",
      "new_cluster": {
        "autoscale": {
          "max_workers":2,
          "min_workers":1
        },
        "azure_attributes": {
          "availability":"ON_DEMAND_AZURE",
          "spot_bid_max_price":100
        },
        "data_security_mode":"SINGLE_USER",
        "enable_elastic_disk":true,
        "node_type_id":"Standard_DS3_v2",
        "policy_id":"000C31E193543DF5",
        "spark_version":"16.4.x-scala2.12"
      }
    }
  ],
  "job_id":266854261681287,
  "job_parameters": [
    {
      "default":"mock_data/fixtures/dim_rule_scd2.json",
      "name":"seed_path",
      "value":"mock_data/fixtures/dim_rule_scd2.json"
    },
    {
      "default":"gold.dim_rule_scd2",
      "name":"table_name",
      "value":"gold.dim_rule_scd2"
    }
  ],
  "job_run_id":792623066751391,
  "number_in_job":792623066751391,
  "original_attempt_run_id":792623066751391,
  "run_duration":182952,
  "run_id":792623066751391,
  "run_name":"data-pipeline-sync-rules-dev",
  "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/266854261681287/run/792623066751391",
  "run_type":"JOB_RUN",
  "setup_duration":100000,
  "start_time":1770820401653,
  "state": {
    "life_cycle_state":"TERMINATED",
    "result_state":"SUCCESS",
    "state_message":"",
    "user_cancelled_or_timedout":false
  },
  "status": {
    "state":"TERMINATED",
    "termination_details": {
      "code":"SUCCESS",
      "message":"",
      "type":"SUCCESS"
    }
  },
  "tasks": [
    {
      "attempt_number":0,
      "cleanup_duration":0,
      "cluster_instance": {
        "cluster_id":"0211-143322-k9raqwf9",
        "spark_context_id":"8734619507216929239"
      },
      "end_time":1770820584335,
      "execution_duration":82000,
      "job_cluster_key":"policy_single_node",
      "run_id":473230776951156,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/266854261681287/run/473230776951156",
      "setup_duration":100000,
      "spark_python_task": {
        "parameters": [
          "--catalog",
          "hive_metastore",
          "--seed-path",
          "{{job.parameters.seed_path}}",
          "--table-name",
          "{{job.parameters.table_name}}"
        ],
        "python_file":"/Workspace/Users/2dt026@msacademy.msai.kr/.bundle/data-pipeline/dev/files/scripts/sync_dim_rule_scd2.py",
        "source":"WORKSPACE"
      },
      "start_time":1770820401675,
      "state": {
        "life_cycle_state":"TERMINATED",
        "result_state":"SUCCESS",
        "state_message":"",
        "user_cancelled_or_timedout":false
      },
      "status": {
        "state":"TERMINATED",
        "termination_details": {
          "code":"SUCCESS",
          "message":"",
          "type":"SUCCESS"
        }
      },
      "task_key":"sync_rule_table"
    }
  ],
  "trigger":"ONE_TIME"
}
2026-02-11T14:36:31Z run_id=792623066751391 state=TERMINATED/SUCCESS msg=
sync_dim_rule_scd2: SUCCESS
\n### e2e_setup_mock_data
job_parameters={"scenario":"","run_id":"l3_d036_param_20260211T143321Z"}
{
  "cleanup_duration":0,
  "creator_user_name":"2dt026@msacademy.msai.kr",
  "end_time":1770820858141,
  "execution_duration":165000,
  "job_clusters": [
    {
      "job_cluster_key":"policy_cluster",
      "new_cluster": {
        "autoscale": {
          "max_workers":2,
          "min_workers":1
        },
        "azure_attributes": {
          "availability":"ON_DEMAND_AZURE",
          "spot_bid_max_price":100
        },
        "data_security_mode":"SINGLE_USER",
        "enable_elastic_disk":true,
        "node_type_id":"Standard_DS3_v2",
        "policy_id":"000C31E193543DF5",
        "spark_version":"16.4.x-scala2.12"
      }
    }
  ],
  "job_id":920043826442932,
  "job_parameters": [
    {
      "default":"",
      "name":"scenario",
      "value":""
    },
    {
      "default":"",
      "name":"run_id",
      "value":"l3_d036_param_20260211T143321Z"
    }
  ],
  "job_run_id":979561404872200,
  "number_in_job":979561404872200,
  "original_attempt_run_id":979561404872200,
  "run_duration":266616,
  "run_id":979561404872200,
  "run_name":"data-pipeline-e2e-setup-dev",
  "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/920043826442932/run/979561404872200",
  "run_type":"JOB_RUN",
  "setup_duration":101000,
  "start_time":1770820591525,
  "state": {
    "life_cycle_state":"TERMINATED",
    "result_state":"SUCCESS",
    "state_message":"",
    "user_cancelled_or_timedout":false
  },
  "status": {
    "state":"TERMINATED",
    "termination_details": {
      "code":"SUCCESS",
      "message":"",
      "type":"SUCCESS"
    }
  },
  "tasks": [
    {
      "attempt_number":0,
      "cleanup_duration":0,
      "cluster_instance": {
        "cluster_id":"0211-143632-j5p0c5ut",
        "spark_context_id":"8712368551462861969"
      },
      "end_time":1770820857861,
      "execution_duration":165000,
      "job_cluster_key":"policy_cluster",
      "run_id":16872528117507,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/920043826442932/run/16872528117507",
      "setup_duration":101000,
      "spark_python_task": {
        "parameters": [
          "--catalog",
          "hive_metastore",
          "--scenario",
          "{{job.parameters.scenario}}",
          "--run-id",
          "{{job.parameters.run_id}}",
          "--drop-existing"
        ],
        "python_file":"/Workspace/Users/2dt026@msacademy.msai.kr/.bundle/data-pipeline/dev/files/scripts/e2e/setup_e2e_env.py",
        "source":"WORKSPACE"
      },
      "start_time":1770820591545,
      "state": {
        "life_cycle_state":"TERMINATED",
        "result_state":"SUCCESS",
        "state_message":"",
        "user_cancelled_or_timedout":false
      },
      "status": {
        "state":"TERMINATED",
        "termination_details": {
          "code":"SUCCESS",
          "message":"",
          "type":"SUCCESS"
        }
      },
      "task_key":"setup_e2e_env"
    }
  ],
  "trigger":"ONE_TIME"
}
2026-02-11T14:41:03Z run_id=979561404872200 state=TERMINATED/SUCCESS msg=
e2e_setup_mock_data: SUCCESS
\n### e2e_full_pipeline
job_parameters={"run_mode":"incremental","start_ts":"2026-02-11T12:33:21Z","end_ts":"2026-02-11T14:33:21Z","date_kst_start":"","date_kst_end":"","run_id":"l3_d036_param_20260211T143321Z"}
{
  "cleanup_duration":0,
  "creator_user_name":"2dt026@msacademy.msai.kr",
  "end_time":1770821111291,
  "execution_duration":0,
  "job_clusters": [
    {
      "job_cluster_key":"policy_single_node",
      "new_cluster": {
        "autoscale": {
          "max_workers":2,
          "min_workers":1
        },
        "azure_attributes": {
          "availability":"ON_DEMAND_AZURE",
          "spot_bid_max_price":100
        },
        "data_security_mode":"SINGLE_USER",
        "enable_elastic_disk":true,
        "node_type_id":"Standard_DS3_v2",
        "policy_id":"000C31E193543DF5",
        "spark_version":"16.4.x-scala2.12"
      }
    }
  ],
  "job_id":1014961373700837,
  "job_parameters": [
    {
      "default":"incremental",
      "name":"run_mode",
      "value":"incremental"
    },
    {
      "default":"",
      "name":"start_ts",
      "value":"2026-02-11T12:33:21Z"
    },
    {
      "default":"",
      "name":"end_ts",
      "value":"2026-02-11T14:33:21Z"
    },
    {
      "default":"",
      "name":"date_kst_start",
      "value":""
    },
    {
      "default":"",
      "name":"date_kst_end",
      "value":""
    },
    {
      "default":"",
      "name":"run_id",
      "value":"l3_d036_param_20260211T143321Z"
    },
    {
      "default":"fallback",
      "name":"rule_load_mode"
    },
    {
      "default":"gold.dim_rule_scd2",
      "name":"rule_table"
    },
    {
      "default":"mock_data/fixtures/dim_rule_scd2.json",
      "name":"rule_seed_path"
    }
  ],
  "job_run_id":866631229979925,
  "number_in_job":866631229979925,
  "original_attempt_run_id":866631229979925,
  "run_duration":248921,
  "run_id":866631229979925,
  "run_name":"data-pipeline-e2e-full-dev",
  "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/1014961373700837/run/866631229979925",
  "run_type":"JOB_RUN",
  "setup_duration":0,
  "start_time":1770820862370,
  "state": {
    "life_cycle_state":"TERMINATED",
    "result_state":"SUCCESS",
    "state_message":"",
    "user_cancelled_or_timedout":false
  },
  "status": {
    "state":"TERMINATED",
    "termination_details": {
      "code":"SUCCESS",
      "message":"",
      "type":"SUCCESS"
    }
  },
  "tasks": [
    {
      "attempt_number":0,
      "cleanup_duration":0,
      "cluster_instance": {
        "cluster_id":"0211-144103-r33s3s11",
        "spark_context_id":"4954286065944199639"
      },
      "end_time":1770821056896,
      "execution_duration":88000,
      "job_cluster_key":"policy_single_node",
      "run_id":764143392755986,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/1014961373700837/run/764143392755986",
      "setup_duration":106000,
      "spark_python_task": {
        "parameters": [
          "--catalog",
          "hive_metastore",
          "--run-mode",
          "{{job.parameters.run_mode}}",
          "--start-ts",
          "{{job.parameters.start_ts}}",
          "--end-ts",
          "{{job.parameters.end_ts}}",
          "--date-kst-start",
          "{{job.parameters.date_kst_start}}",
          "--date-kst-end",
          "{{job.parameters.date_kst_end}}",
          "--run-id",
          "{{job.parameters.run_id}}",
          "--rule-load-mode",
          "{{job.parameters.rule_load_mode}}",
          "--rule-table",
          "{{job.parameters.rule_table}}",
          "--rule-seed-path",
          "{{job.parameters.rule_seed_path}}"
        ],
        "python_file":"/Workspace/Users/2dt026@msacademy.msai.kr/.bundle/data-pipeline/dev/files/scripts/run_pipeline_a.py",
        "source":"WORKSPACE"
      },
      "start_time":1770820862405,
      "state": {
        "life_cycle_state":"TERMINATED",
        "result_state":"SUCCESS",
        "state_message":"",
        "user_cancelled_or_timedout":false
      },
      "status": {
        "state":"TERMINATED",
        "termination_details": {
          "code":"SUCCESS",
          "message":"",
          "type":"SUCCESS"
        }
      },
      "task_key":"pipeline_a"
    },
    {
      "attempt_number":0,
      "cleanup_duration":0,
      "cluster_instance": {
        "cluster_id":"0211-144103-r33s3s11",
        "spark_context_id":"4954286065944199639"
      },
      "depends_on": [
        {
          "task_key":"pipeline_a"
        }
      ],
      "end_time":1770821080438,
      "execution_duration":23000,
      "job_cluster_key":"policy_single_node",
      "run_id":750886162560883,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/1014961373700837/run/750886162560883",
      "setup_duration":0,
      "spark_python_task": {
        "parameters": [
          "--catalog",
          "hive_metastore",
          "--run-mode",
          "{{job.parameters.run_mode}}",
          "--start-ts",
          "{{job.parameters.start_ts}}",
          "--end-ts",
          "{{job.parameters.end_ts}}",
          "--date-kst-start",
          "{{job.parameters.date_kst_start}}",
          "--date-kst-end",
          "{{job.parameters.date_kst_end}}",
          "--run-id",
          "{{job.parameters.run_id}}"
        ],
        "python_file":"/Workspace/Users/2dt026@msacademy.msai.kr/.bundle/data-pipeline/dev/files/scripts/run_pipeline_c.py",
        "source":"WORKSPACE"
      },
      "start_time":1770821057182,
      "state": {
        "life_cycle_state":"TERMINATED",
        "result_state":"SUCCESS",
        "state_message":"",
        "user_cancelled_or_timedout":false
      },
      "status": {
        "state":"TERMINATED",
        "termination_details": {
          "code":"SUCCESS",
          "message":"",
          "type":"SUCCESS"
        }
      },
      "task_key":"pipeline_c"
    },
    {
      "attempt_number":0,
      "cleanup_duration":0,
      "cluster_instance": {
        "cluster_id":"0211-144103-r33s3s11",
        "spark_context_id":"4954286065944199639"
      },
      "depends_on": [
        {
          "task_key":"pipeline_a"
        }
      ],
      "end_time":1770821111057,
      "execution_duration":53000,
      "job_cluster_key":"policy_single_node",
      "run_id":131761419139941,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/1014961373700837/run/131761419139941",
      "setup_duration":0,
      "spark_python_task": {
        "parameters": [
          "--catalog",
          "hive_metastore",
          "--run-mode",
          "{{job.parameters.run_mode}}",
          "--start-ts",
          "{{job.parameters.start_ts}}",
          "--end-ts",
          "{{job.parameters.end_ts}}",
          "--date-kst-start",
          "{{job.parameters.date_kst_start}}",
          "--date-kst-end",
          "{{job.parameters.date_kst_end}}",
          "--run-id",
          "{{job.parameters.run_id}}",
          "--rule-load-mode",
          "{{job.parameters.rule_load_mode}}",
          "--rule-table",
          "{{job.parameters.rule_table}}",
          "--rule-seed-path",
          "{{job.parameters.rule_seed_path}}"
        ],
        "python_file":"/Workspace/Users/2dt026@msacademy.msai.kr/.bundle/data-pipeline/dev/files/scripts/run_pipeline_b.py",
        "source":"WORKSPACE"
      },
      "start_time":1770821057113,
      "state": {
        "life_cycle_state":"TERMINATED",
        "result_state":"SUCCESS",
        "state_message":"",
        "user_cancelled_or_timedout":false
      },
      "status": {
        "state":"TERMINATED",
        "termination_details": {
          "code":"SUCCESS",
          "message":"",
          "type":"SUCCESS"
        }
      },
      "task_key":"pipeline_b"
    }
  ],
  "trigger":"ONE_TIME"
}
2026-02-11T14:45:13Z run_id=866631229979925 state=TERMINATED/SUCCESS msg=
e2e_full_pipeline: SUCCESS
\n## Result\n- Overall: SUCCESS
