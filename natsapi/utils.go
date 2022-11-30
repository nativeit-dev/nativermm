package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"io/ioutil"
	"time"

	"github.com/jmoiron/sqlx"
	_ "github.com/lib/pq"
	nativermm "github.com/nativeit/nativermm-shared"
	nats "github.com/nats-io/nats.go"
)

func setupNatsOptions(key string) []nats.Option {
	opts := []nats.Option{
		nats.Name("NativeRMM"),
		nats.UserInfo("nativermm", key),
		nats.ReconnectWait(time.Second * 2),
		nats.RetryOnFailedConnect(true),
		nats.MaxReconnects(-1),
		nats.ReconnectBufSize(-1),
	}
	return opts
}

func GetConfig(cfg string) (db *sqlx.DB, r DjangoConfig, err error) {
	if cfg == "" {
		cfg = "/rmm/api/nativermm/nats-api.conf"
		if !nativermm.FileExists(cfg) {
			err = errors.New("unable to find config file")
			return
		}
	}

	jret, _ := ioutil.ReadFile(cfg)
	err = json.Unmarshal(jret, &r)
	if err != nil {
		return
	}

	psqlInfo := fmt.Sprintf("host=%s port=%d user=%s "+
		"password=%s dbname=%s sslmode=%s",
		r.Host, r.Port, r.User, r.Pass, r.DBName, r.SSLMode)

	db, err = sqlx.Connect("postgres", psqlInfo)
	if err != nil {
		return
	}
	db.SetMaxOpenConns(20)
	return
}
