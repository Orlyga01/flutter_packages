bool isEmpty(dynamic field) {
  return ((field == null) ||
      field == 0 ||
      field.length == 0 ||
      (field == false));
}