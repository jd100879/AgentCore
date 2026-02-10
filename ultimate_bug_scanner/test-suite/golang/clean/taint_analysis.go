package main

import (
    "database/sql"
    "fmt"
    "html"
    "net/http"
    "os/exec"
    "path/filepath"
)

var db *sql.DB

func render(w http.ResponseWriter, r *http.Request) {
    comment := html.EscapeString(r.FormValue("comment"))
    htmlBody := fmt.Sprintf("<div>%s</div>", comment)
    fmt.Fprint(w, htmlBody)
}

func queryUser(w http.ResponseWriter, r *http.Request) {
    username := r.FormValue("user")
    db.Exec("SELECT * FROM users WHERE username = ?", username)
}

func runCmd(w http.ResponseWriter, r *http.Request) {
    path := filepath.Clean(r.FormValue("path"))
    exec.Command("ls", path).Run()
}

func main() {}
