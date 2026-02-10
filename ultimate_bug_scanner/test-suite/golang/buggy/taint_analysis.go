package main

import (
    "database/sql"
    "fmt"
    "net/http"
    "os/exec"
)

var db *sql.DB

func render(w http.ResponseWriter, r *http.Request) {
    comment := r.FormValue("comment")
    html := fmt.Sprintf("<div>%s</div>", comment)
    fmt.Fprintf(w, html)
}

func queryUser(w http.ResponseWriter, r *http.Request) {
    username := r.FormValue("user")
    sql := "SELECT * FROM users WHERE username = '" + username + "'"
    db.Exec(sql)
}

func runCmd(w http.ResponseWriter, r *http.Request) {
    path := r.FormValue("path")
    exec.Command("sh", "-c", "ls "+path).Run()
}

func main() {}
