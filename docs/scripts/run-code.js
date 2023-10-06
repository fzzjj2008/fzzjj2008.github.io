function runCode(objname) {
  var winname = window.open('', "_blank", '');
  var obj = document.getElementById(objname);
  winname.document.open('text/html', 'replace');
  winname.opener = null
  winname.document.write(obj.value);
  winname.document.close();
}
