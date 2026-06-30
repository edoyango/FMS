/***********************************************************************
 *                             Apache License 2.0
 *
 * This file is part of the GFDL Flexible Modeling System (FMS).
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * FMS is distributed in the hope that it will be useful, but WITHOUT
 * WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied;
 * without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
 * PARTICULAR PURPOSE. See the License for the specific language
 * governing permissions and limitations under the License.
 ***********************************************************************/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// struct to store a string and id associated with that string
typedef struct{
  char *arr_name;
  size_t arr_len;
  int id;
}my_type;

static size_t bounded_strlen(const char *str, size_t max_len)
{
  const char *nul = memchr(str, '\0', max_len);
  if (nul != NULL) return (size_t)(nul - str);
  return max_len;
}

static int bounded_strcmp(const char *str1, size_t len1, const char *str2, size_t len2)
{
  size_t min_len = len1 < len2 ? len1 : len2;
  int cmp;

  if (min_len > 0) {
    cmp = memcmp(str1, str2, min_len);
    if (cmp != 0) return cmp;
  }

  if (len1 < len2) return -1;
  if (len1 > len2) return 1;
  return 0;
}

static void free_sort_records(my_type *the_type, int n)
{
  int i;

  if (the_type == NULL) return;
  for (i = 0; i < n; i++) {
    free(the_type[i].arr_name);
  }
  free(the_type);
}

static void copy_record_to_slot(char *slot, size_t slot_len, const my_type *record)
{
  size_t copy_len = record->arr_len < slot_len ? record->arr_len : slot_len;

  if (copy_len > 0) memcpy(slot, record->arr_name, copy_len);
  if (copy_len < slot_len) {
    slot[copy_len] = '\0';
    if (copy_len + 1 < slot_len) {
      memset(slot + copy_len + 1, ' ', slot_len - copy_len - 1);
    }
  }
}

// Compares two my_type types by the arr_name
static int arr_name_sorter(const void* p1, const void* p2)
{
  const my_type *the_type1 = p1;
  const my_type *the_type2 = p2;

  return bounded_strcmp(the_type1->arr_name, the_type1->arr_len, the_type2->arr_name, the_type2->arr_len);
}

// Sorts an array of fixed-size string slots in alphabetical order
// arr -> pointer of character array
// n -> length of the array
// string_len -> fixed length of each string slot
// id - > indices of the character array
static void fms_sort_this_len_impl(char **arr, int* n, int* string_len, int* id)
{
  int i; // For do loops
  my_type *the_type;
  size_t slot_len;

  if (*n <= 1) return;
  if (*string_len <= 0) return;
  slot_len = (size_t)(*string_len);

  // Save the array and the id into a struct
  the_type = (my_type*)calloc(*n, sizeof(my_type));
  if (the_type == NULL) {
    fprintf(stderr, "fms_sort_this: failed to allocate sort records\n");
    exit(EXIT_FAILURE);
  }

  for(i=0; i<*n; i++){
    the_type[i].id = id[i];
    the_type[i].arr_len = bounded_strlen(arr[i], slot_len);
    the_type[i].arr_name = (char*)malloc(the_type[i].arr_len == 0 ? 1 : the_type[i].arr_len);
    if (the_type[i].arr_name == NULL) {
      fprintf(stderr, "fms_sort_this: failed to allocate sort record string\n");
      free_sort_records(the_type, *n);
      exit(EXIT_FAILURE);
    }
    if (the_type[i].arr_len > 0) memcpy(the_type[i].arr_name, arr[i], the_type[i].arr_len);
  }

  qsort(the_type, *n, sizeof(my_type), arr_name_sorter);

  // Copy the sorted array and the sorted ids
  for(i=0; i<*n; i++){
    id[i] = the_type[i].id;
    copy_record_to_slot(arr[i], slot_len, &the_type[i]);
  }

  free_sort_records(the_type, *n);
}

void fms_sort_this_len(char **arr, int* n, int* string_len, int* id)
{
  fms_sort_this_len_impl(arr, n, string_len, id);
}

// Implements a binary search to search for a string in an array of strings
// arr -> pointer of character array
// n -> length of the array
// find me -> string to find
// np -> the number of times the string was found
// returns a string with the indices ;)
char* fms_find_my_string_binding(char** arr, int *n, char *find_me, int *np)
{
  int L= 0;     // Left bound
  int R = *n;   // Right bound
  int m;        // Middle of the bound
  int mm;       // Index currently looking at
  int is_found; // Result from strcmp: 0 if string was found  <0 if the string is "less" >0 if the string is "greater"
  int *p;       // Array to store the indices
  int i;        // For do loops

  *np = 0;
  is_found = -1;
  while(L != R){
    // Start looking in the midle of the array
	  m = ceil((L + R) / 2);
    //printf("L is set to %i from L=%i and R=%i \n", m, L, R);

    //printf("Checking %i:%s \n", m, (arr[m]));
	  is_found = strcmp(find_me,(arr[m]));
	  if (is_found == 0)
	  {
      *np = 1;
      p = malloc(sizeof(int) * *np);
      p[*np-1] = m + 1; //Because fortran indices start at 1 ;)
      //printf("Array found at %i %i %i \n", *np, m, p[*np-1]);

      // The string can be found in multiple indices of the array, so look to the left of the index where the string
      // was initially found
      mm = m;
      while (is_found == 0) {
        if (mm != 0) { // Only look to the left if m is not the begining of the array
			    mm= mm -1;
          is_found = strcmp(find_me,(arr[mm]));
			    if (is_found == 0 ) {
            *np = *np + 1;
            p = realloc(p, sizeof(int) * *np);
            p[*np-1] = mm + 1;
            //printf("Array found at %i %i %i\n", *np, mm, p[*np-1]);
          }
        } else {is_found = -999;} //Done looking
		  }
      // The string can be found in multiple indices of the array, so look to the right of the index where the string was
      // initially found
		  mm = m;
		  is_found =0;
      while (is_found == 0) {
        if (mm != *n-1) { // Only look to the right if m is not the end of the array
          mm = mm + 1;
          is_found = strcmp(find_me,(arr[mm]));
          if (is_found == 0 ) {
            *np = *np + 1;
            p = realloc(p, sizeof(int) * *np);
		        p[*np-1] = mm + 1;
            //printf("Array found at %i %i %i\n", *np, mm, p[*np-1]);
         }
        } else {is_found = -999;} //Done looking}
      }
		  L = R;
      // If find_me is greater than arr[m] (i.e find_me="potato" is greater than arr[m]="banana")
	  } else if (is_found > 0) {
      // Set the lower bound to start in m (ignore the first half)
  	  L = m + 1;
      //printf("L is set to %i \n", L);
    } else
    // If find_me is less than arr[m] (i.e find_me="potato" is less than arr[m] = "soccer")
    {
      // Set the upper bound to start in m (ignore the lower half)
      R = m;
      //printf("R is set to %i \n", R);
	}

}

  // This is the magical part:
  // Save the array of indices where the string was found into a string
  // The fortran side is going to allocate the array to the correct size and read the string into the array
  // The alternative (normal) way is to have a separate function that gets the number of times the string is found
  // The fortran side will allocate the array to the correct size and send that into another function that
  // fill in that array. That will require you to search through the array twice ...
  char string[255];
  char *string_p;

  strcpy(string, "");

  for(i=0; i<*np; i++){
    if (i == *np-1) {sprintf( &string[ strlen(string) ],  "%d ", p[i] );}
    else {sprintf( &string[ strlen(string) ],  "%d ,", p[i] );}
  }

  string_p = (char*) malloc((strlen(string)+1)*sizeof(char));
  strcpy(string_p, string);
  return string_p;
}

/*!
 * @brief Finds the number of unique strings in an array
 * @param[in]  arr Array of strings
 * @param[in]  n   Size of the array
 * @return Number of unique strings in an array
 */
int fms_find_unique(char** arr, int *n)
{
  int i, j; // For loops
  int nfind; // Number of unique strings in an array

  if (*n <= 0) return 0;

  nfind=0;
  for(i=0; i<*n; i++){
    int found = 0;
    for(j=0; j<i; j++){
      if (strcmp(arr[i], arr[j]) == 0) {
        found = 1;
        break;
      }
    }
    if (!found) nfind = nfind + 1;
  }

  return nfind;
}

/*!
 * @brief Returns a c string pointer
 * @param[in] cs  Input c string pointer
 * @return c string pointer
 */
char * cstring2cpointer (char * cs)
{
	return cs;
}
