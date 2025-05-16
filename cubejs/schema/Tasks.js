cube(`Tasks`, {
  sql: `SELECT * FROM ${CLICKHOUSE_DB}.support_tasks`,

  preAggregations: {
    // Define pre-aggregations for faster queries
    tasksByDepartment: {
      measures: [Tasks.count],
      dimensions: [Tasks.department, Tasks.product],
      timeDimension: Tasks.actionAt,
      granularity: 'day'
    }
  },

  measures: {
    count: {
      type: `count`,
      drillMembers: [taskId, client, createdAt]
    },

    avgResponseTime: {
      sql: `dateDiff('minute', createddatetime, actdatetime)`,
      type: `avg`,
      title: `Average Response Time (minutes)`
    },

    maxResponseTime: {
      sql: `dateDiff('minute', createddatetime, actdatetime)`,
      type: `max`,
      title: `Max Response Time (minutes)`
    }
  },

  dimensions: {
    taskId: {
      sql: `task_id`,
      type: `string`,
      primaryKey: true,
      title: `Task ID`
    },

    client: {
      sql: `client`,
      type: `string`
    },

    status: {
      sql: `status12`,
      type: `string`
    },

    department: {
      sql: `dept_descr`,
      type: `string`
    },

    division: {
      sql: `div_descr`,
      type: `string`
    },

    jobClassification: {
      sql: `job_classification`,
      type: `string`,
      title: `Job Classification`
    },

    isLive: {
      sql: `liveissue = 'Y'`,
      type: `boolean`,
      title: `Is Live Issue`
    },

    taskClass: {
      sql: `task_class`,
      type: `string`,
      title: `Task Class`
    },

    product: {
      sql: `product`,
      type: `string`
    },

    createdAt: {
      sql: `createddatetime`,
      type: `time`,
      title: `Created At`
    },

    actionAt: {
      sql: `actdatetime`,
      type: `time`,
      title: `Action At`
    }
  }
});

cube(`TaskPerformance`, {
  sql: `SELECT * FROM ${CLICKHOUSE_DB}.task_performance`,

  measures: {
    avgResponseTimeHours: {
      sql: `response_time_hours`,
      type: `avg`,
      title: `Average Response Time (hours)`
    },

    medianResponseTimeHours: {
      sql: `response_time_hours`,
      type: `median`,
      title: `Median Response Time (hours)`
    },

    countTasks: {
      sql: `task_id`,
      type: `countDistinct`,
      title: `Number of Tasks`
    }
  },

  dimensions: {
    department: {
      sql: `department`,
      type: `string`
    },

    division: {
      sql: `division`,
      type: `string`
    },

    product: {
      sql: `product`,
      type: `string`
    },

    taskClass: {
      sql: `task_class`,
      type: `string`,
      title: `Task Class`
    },

    responseTimeCategory: {
      type: `string`,
      case: {
        when: [{
          sql: `response_time_hours < 1`,
          label: `Under 1 hour`
        }, {
          sql: `response_time_hours < 4`,
          label: `1-4 hours`
        }, {
          sql: `response_time_hours < 24`,
          label: `4-24 hours`
        }, {
          sql: `response_time_hours < 72`,
          label: `1-3 days`
        }],
        else: {
          label: `Over 3 days`
        }
      },
      title: `Response Time Category`
    },

    createdAt: {
      sql: `created_at`,
      type: `time`,
      title: `Created At`
    }
  }
});
