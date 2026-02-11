# D-036 L3 verification (sync job path)

- started_utc=2026-02-11T14:11:22Z
- poll_seconds=30
- timeout_seconds=900
- run_id=l3_d036_sync_20260211T141122Z
- job_id.bootstrap=384422610745672
- job_id.sync=266854261681287
- job_id.setup=920043826442932
- job_id.e2e_full=1014961373700837
- start_ts=2026-02-11T12:11:22Z
- end_ts=2026-02-11T14:11:22Z

## Run log
\n### bootstrap_catalog
job_parameters={}
{
  "cleanup_duration":0,
  "creator_user_name":"2dt026@msacademy.msai.kr",
  "end_time":1770819404119,
  "execution_duration":55000,
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
  "job_id":384422610745672,
  "job_run_id":943813169655315,
  "number_in_job":943813169655315,
  "original_attempt_run_id":943813169655315,
  "run_duration":321970,
  "run_id":943813169655315,
  "run_name":"data-pipeline-bootstrap-dev",
  "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/384422610745672/run/943813169655315",
  "run_type":"JOB_RUN",
  "setup_duration":266000,
  "start_time":1770819082149,
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
        "cluster_id":"0211-141122-7pyo1aqt",
        "spark_context_id":"3966228357681316754"
      },
      "end_time":1770819403753,
      "execution_duration":55000,
      "job_cluster_key":"policy_single_node",
      "run_id":807642578780168,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/384422610745672/run/807642578780168",
      "setup_duration":266000,
      "spark_python_task": {
        "parameters": [
          "--catalog",
          "hive_metastore"
        ],
        "python_file":"/Workspace/Users/2dt026@msacademy.msai.kr/.bundle/data-pipeline/dev/files/scripts/bootstrap_catalog.py",
        "source":"WORKSPACE"
      },
      "start_time":1770819082177,
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
      "task_key":"bootstrap_schemas_and_tables"
    }
  ],
  "trigger":"ONE_TIME"
}
2026-02-11T14:16:54Z run_id=943813169655315 state=TERMINATED/SUCCESS msg=
bootstrap_catalog: SUCCESS
\n### sync_dim_rule_scd2
job_parameters={"seed_path":"mock_data/fixtures/dim_rule_scd2.json","table_name":"gold.dim_rule_scd2"}
{
  "cleanup_duration":0,
  "creator_user_name":"2dt026@msacademy.msai.kr",
  "end_time":1770819619906,
  "execution_duration":90000,
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
  "job_run_id":1044675993688559,
  "number_in_job":1044675993688559,
  "original_attempt_run_id":1044675993688559,
  "run_duration":205845,
  "run_id":1044675993688559,
  "run_name":"data-pipeline-sync-rules-dev",
  "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/266854261681287/run/1044675993688559",
  "run_type":"JOB_RUN",
  "setup_duration":115000,
  "start_time":1770819414061,
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
        "cluster_id":"0211-141654-5nhs77ad",
        "spark_context_id":"1532832654027212617"
      },
      "end_time":1770819619668,
      "execution_duration":90000,
      "job_cluster_key":"policy_single_node",
      "run_id":1044094030515830,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/266854261681287/run/1044094030515830",
      "setup_duration":115000,
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
      "start_time":1770819414085,
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
2026-02-11T14:20:24Z run_id=1044675993688559 state=TERMINATED/SUCCESS msg=
sync_dim_rule_scd2: SUCCESS
\n### e2e_setup_mock_data
job_parameters={"scenario":"","run_id":"l3_d036_sync_20260211T141122Z"}
{
  "cleanup_duration":0,
  "creator_user_name":"2dt026@msacademy.msai.kr",
  "end_time":1770819915992,
  "execution_duration":180000,
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
      "value":"l3_d036_sync_20260211T141122Z"
    }
  ],
  "job_run_id":814813210923566,
  "number_in_job":814813210923566,
  "original_attempt_run_id":814813210923566,
  "run_duration":292015,
  "run_id":814813210923566,
  "run_name":"data-pipeline-e2e-setup-dev",
  "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/920043826442932/run/814813210923566",
  "run_type":"JOB_RUN",
  "setup_duration":111000,
  "start_time":1770819623977,
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
        "cluster_id":"0211-142024-5dt6jqud",
        "spark_context_id":"2167306443587312909"
      },
      "end_time":1770819915687,
      "execution_duration":180000,
      "job_cluster_key":"policy_cluster",
      "run_id":359294342306363,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/920043826442932/run/359294342306363",
      "setup_duration":111000,
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
      "start_time":1770819624003,
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
2026-02-11T14:25:24Z run_id=814813210923566 state=TERMINATED/SUCCESS msg=
e2e_setup_mock_data: SUCCESS
\n### e2e_full_pipeline
job_parameters={"run_mode":"incremental","start_ts":"2026-02-11T12:11:22Z","end_ts":"2026-02-11T14:11:22Z","date_kst_start":"","date_kst_end":"","run_id":"l3_d036_sync_20260211T141122Z"}
{
  "cleanup_duration":0,
  "creator_user_name":"2dt026@msacademy.msai.kr",
  "end_time":1770820170645,
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
      "value":"2026-02-11T12:11:22Z"
    },
    {
      "default":"",
      "name":"end_ts",
      "value":"2026-02-11T14:11:22Z"
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
      "value":"l3_d036_sync_20260211T141122Z"
    }
  ],
  "job_run_id":366417393987253,
  "number_in_job":366417393987253,
  "original_attempt_run_id":366417393987253,
  "run_duration":246083,
  "run_id":366417393987253,
  "run_name":"data-pipeline-e2e-full-dev",
  "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/1014961373700837/run/366417393987253",
  "run_type":"JOB_RUN",
  "setup_duration":0,
  "start_time":1770819924562,
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
        "cluster_id":"0211-142525-nszhu2ed",
        "spark_context_id":"5384384466470422887"
      },
      "end_time":1770820117307,
      "execution_duration":91000,
      "job_cluster_key":"policy_single_node",
      "run_id":676664169219044,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/1014961373700837/run/676664169219044",
      "setup_duration":101000,
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
        "python_file":"/Workspace/Users/2dt026@msacademy.msai.kr/.bundle/data-pipeline/dev/files/scripts/run_pipeline_a.py",
        "source":"WORKSPACE"
      },
      "start_time":1770819924586,
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
        "cluster_id":"0211-142525-nszhu2ed",
        "spark_context_id":"5384384466470422887"
      },
      "depends_on": [
        {
          "task_key":"pipeline_a"
        }
      ],
      "end_time":1770820144253,
      "execution_duration":26000,
      "job_cluster_key":"policy_single_node",
      "run_id":962382863150850,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/1014961373700837/run/962382863150850",
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
      "start_time":1770820117543,
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
        "cluster_id":"0211-142525-nszhu2ed",
        "spark_context_id":"5384384466470422887"
      },
      "depends_on": [
        {
          "task_key":"pipeline_a"
        }
      ],
      "end_time":1770820170410,
      "execution_duration":52000,
      "job_cluster_key":"policy_single_node",
      "run_id":416141049624607,
      "run_if":"ALL_SUCCESS",
      "run_page_url":"https://adb-7405617667923145.5.azuredatabricks.net/?o=7405617667923145#job/1014961373700837/run/416141049624607",
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
        "python_file":"/Workspace/Users/2dt026@msacademy.msai.kr/.bundle/data-pipeline/dev/files/scripts/run_pipeline_b.py",
        "source":"WORKSPACE"
      },
      "start_time":1770820117475,
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
2026-02-11T14:29:35Z run_id=366417393987253 state=TERMINATED/SUCCESS msg=
e2e_full_pipeline: SUCCESS
\n## Result\n- Overall: SUCCESS
