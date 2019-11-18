\c postgres

DROP DATABASE faculty_portal;

CREATE DATABASE faculty_portal;

\c faculty_portal


/*-------------------------------------------------------------------------------------------------------------*/

/* changing emp_id is not allowed in any of the tables */
/* leaving the institute means deleting from employee table, and inserting automatically by trigger in deleted_employee table */
CREATE TABLE employee(
	emp_id SERIAL PRIMARY KEY,
	emp_name VARCHAR (255) NOT NULL,
	emp_inst_doj DATE NOT NULL DEFAULT CURRENT_DATE
);

/* read only */
CREATE TABLE deleted_employee(
	emp_id INTEGER PRIMARY KEY,
	emp_name VARCHAR (255) NOT NULL,
	emp_inst_doj DATE NOT NULL,
	emp_inst_dol DATE NOT NULL DEFAULT CURRENT_DATE
);

/* read only */
/* due to this table, emp_id in employee and deleted_employee tables combined can never be same */
CREATE TABLE is_employee_deleted(
	emp_id INTEGER PRIMARY KEY,
	is_deleted BOOLEAN NOT NULL
);


/*-------------------------------------------------------------------------------------------------------------*/

CREATE OR REPLACE FUNCTION check_emp_id_change() RETURNS TRIGGER AS
$$
BEGIN
	IF OLD.emp_id <> NEW.emp_id THEN
		RAISE EXCEPTION 'Employee ID cannot be changed';
	END IF;
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER check_emp_id_change_trigger
BEFORE UPDATE
ON employee
FOR EACH ROW
EXECUTE PROCEDURE check_emp_id_change();


/*-------------------------------------------------------------------------------------------------------------*/

/* this won't allow you to enter a person with same pid again even if it is deleted */
CREATE OR REPLACE FUNCTION populate_is_employee_deleted() RETURNS TRIGGER AS
$$
BEGIN
	INSERT INTO is_employee_deleted (emp_id, is_deleted) VALUES (NEW.emp_id, FALSE);
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER populate_is_employee_deleted_trigger
BEFORE INSERT
ON employee
FOR EACH ROW
EXECUTE PROCEDURE populate_is_employee_deleted();


/*-------------------------------------------------------------------------------------------------------------*/

CREATE OR REPLACE FUNCTION log_deleted_employee() RETURNS TRIGGER AS
$$
BEGIN
	INSERT INTO deleted_employee (emp_id, emp_name, emp_inst_doj) VALUES (OLD.emp_id, OLD.emp_name, OLD.emp_inst_doj);
	UPDATE is_employee_deleted SET is_deleted = TRUE WHERE emp_id = OLD.emp_id;
	RETURN OLD;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER log_deleted_employee_trigger
AFTER DELETE
ON employee
FOR EACH ROW
EXECUTE PROCEDURE log_deleted_employee();


/*-------------------------------------------------------------------------------------------------------------*/

CREATE TABLE department(
	dep_name VARCHAR (255) NOT NULL PRIMARY KEY,
	dep_date_of_start DATE NOT NULL DEFAULT CURRENT_DATE
);

/* read only */
CREATE TABLE deleted_department(
	dep_name VARCHAR (255) NOT NULL PRIMARY KEY,
	dep_date_of_start DATE NOT NULL,
	dep_date_of_end DATE NOT NULL DEFAULT CURRENT_DATE
);

/* read only */
CREATE TABLE is_department_deleted(
	dep_name VARCHAR (255) NOT NULL PRIMARY KEY,
	is_deleted BOOLEAN NOT NULL
);


/*-------------------------------------------------------------------------------------------------------------*/

CREATE OR REPLACE FUNCTION update_dep_name() RETURNS TRIGGER AS
$$
BEGIN
	UPDATE is_department_deleted SET dep_name = NEW.dep_name WHERE dep_name = OLD.dep_name;
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER update_dep_name_trigger
BEFORE UPDATE
ON department
FOR EACH ROW
EXECUTE PROCEDURE update_dep_name();


/*-------------------------------------------------------------------------------------------------------------*/

/* this won't allow you to make a new department with same name again even if it is deleted */
CREATE OR REPLACE FUNCTION populate_is_department_deleted() RETURNS TRIGGER AS
$$
BEGIN
	INSERT INTO is_department_deleted (dep_name, is_deleted) VALUES (NEW.dep_name, FALSE);
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER populate_is_department_deleted_trigger
BEFORE INSERT
ON department
FOR EACH ROW
EXECUTE PROCEDURE populate_is_department_deleted();


/*-------------------------------------------------------------------------------------------------------------*/

CREATE OR REPLACE FUNCTION log_deleted_department() RETURNS TRIGGER AS
$$
BEGIN
	INSERT INTO deleted_department (dep_name, dep_date_of_start) VALUES (OLD.dep_name, OLD.dep_date_of_start);
	UPDATE is_department_deleted SET is_deleted = TRUE WHERE dep_name = OLD.dep_name;
	RETURN OLD;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER log_deleted_department_trigger
AFTER DELETE
ON department
FOR EACH ROW
EXECUTE PROCEDURE log_deleted_department();


/*-------------------------------------------------------------------------------------------------------------*/

/* only insertion and deletion allowed, no updates allowed */
CREATE TABLE faculty(
	fac_email VARCHAR (255) NOT NULL PRIMARY KEY,
	password TEXT NOT NULL,
	fac_emp_id INTEGER REFERENCES employee(emp_id) ON DELETE CASCADE NOT NULL,
	fac_dep_name VARCHAR (255) REFERENCES department(dep_name) ON DELETE CASCADE ON UPDATE CASCADE NOT NULL,
	fac_doj_of_dept DATE NOT NULL DEFAULT CURRENT_DATE
);

CREATE TYPE cc_fac_post_choices AS ENUM(
	'adfa',
	'dfa',
	'director'
);

/* no insertion and deletion allowed, only updates allowed */
CREATE TABLE cc_faculty(
	cc_fac_post_email VARCHAR (255) NOT NULL PRIMARY KEY,
	password TEXT NOT NULL,
	cc_fac_post cc_fac_post_choices NOT NULL UNIQUE,
	cc_fac_emp_id INTEGER REFERENCES employee(emp_id) ON DELETE RESTRICT NOT NULL,
	cc_fac_start_date DATE NOT NULL DEFAULT CURRENT_DATE,
	cc_fac_end_date DATE NOT NULL,
	CHECK (cc_fac_start_date < cc_fac_end_date)
);

/* no insertion and deletion allowed, only updates allowed */
/* assumption - hod must be faculty in the department whose hod he is */
/* department of hod can be found from his faculty information */
CREATE TABLE hod(
	hod_post_email VARCHAR (255) NOT NULL PRIMARY KEY,
	password TEXT NOT NULL,
	hod_fac_email VARCHAR (255) REFERENCES faculty(fac_email) ON DELETE RESTRICT NOT NULL,
	hod_start_date DATE NOT NULL DEFAULT CURRENT_DATE,
	hod_end_date DATE NOT NULL,
	CHECK (hod_start_date < hod_end_date)
);


/*-------------------------------------------------------------------------------------------------------------*/

CREATE TYPE which_table_choices AS ENUM(
	'fac',
	'cc_fac',
	'hod'
);

/* what if faculty gets deleted */
CREATE TABLE all_email(
	email VARCHAR (255) NOT NULL PRIMARY KEY,
	which_table which_table_choices NOT NULL
);


/*-------------------------------------------------------------------------------------------------------------*/

CREATE OR REPLACE FUNCTION add_fac_email_to_all_email() RETURNS TRIGGER AS
$$
BEGIN
	INSERT INTO all_email (email, which_table) VALUES (NEW.fac_email, 'fac');
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER add_fac_email_to_all_email_trigger
BEFORE INSERT
ON faculty
FOR EACH ROW
EXECUTE PROCEDURE add_fac_email_to_all_email();


/*-------------------------------------------------------------------------------------------------------------*/

CREATE OR REPLACE FUNCTION add_cc_fac_post_email_to_all_email() RETURNS TRIGGER AS
$$
BEGIN
	INSERT INTO all_email (email, which_table) VALUES (NEW.cc_fac_post_email, 'cc_fac');
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER add_cc_fac_post_email_to_all_email_trigger
BEFORE INSERT
ON cc_faculty
FOR EACH ROW
EXECUTE PROCEDURE add_cc_fac_post_email_to_all_email();


/*-------------------------------------------------------------------------------------------------------------*/

CREATE OR REPLACE FUNCTION add_hod_post_email_to_all_email() RETURNS TRIGGER AS
$$
BEGIN
	INSERT INTO all_email (email, which_table) VALUES (NEW.hod_post_email, 'hod');
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER add_hod_post_email_to_all_email_trigger
BEFORE INSERT
ON hod
FOR EACH ROW
EXECUTE PROCEDURE add_hod_post_email_to_all_email();


/*-------------------------------------------------------------------------------------------------------------*/

CREATE OR REPLACE FUNCTION check_one_hod_per_dep() RETURNS TRIGGER AS
$$
BEGIN
	IF (SELECT faculty.fac_dep_name FROM faculty WHERE faculty.fac_email = NEW.hod_fac_email) = ANY (SELECT faculty.fac_dep_name FROM faculty, hod WHERE faculty.fac_email = hod.hod_fac_email) THEN
		RAISE EXCEPTION 'HOD from the same department already exists';
	END IF;
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER check_one_hod_per_dep_trigger
BEFORE INSERT
ON hod
FOR EACH ROW
EXECUTE PROCEDURE check_one_hod_per_dep();


/*-------------------------------------------------------------------------------------------------------------*/

CREATE OR REPLACE FUNCTION check_changed_hod_dep() RETURNS TRIGGER AS
$$
BEGIN
	IF (SELECT faculty.fac_dep_name FROM faculty WHERE faculty.fac_email = OLD.hod_fac_email) <> (SELECT faculty.fac_dep_name FROM faculty WHERE faculty.fac_email = NEW.hod_fac_email) THEN
		RAISE EXCEPTION 'Department of the changed HOD must be the same as that of the previous HOD';
	END IF;
	RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER check_changed_hod_dep_trigger
BEFORE UPDATE
ON hod
FOR EACH ROW
EXECUTE PROCEDURE check_changed_hod_dep();


/*-------------------------------------------------------------------------------------------------------------*/

/* leave is associated to employee, not post or email */
/* which_table attribute of all_email would allow us to know the post of the employee when the application was launched */
CREATE TABLE curr_leave_application(
	app_id SERIAL PRIMARY KEY,
	/* unique constraint is used because at one time, an employee can launch only 1 leave application */
	/* if someone leaves institute while his application was in process, delete that application */
	launched_by_emp_id INTEGER REFERENCES employee(emp_id) ON DELETE CASCADE NOT NULL UNIQUE,
	/* this need not be unique */
	/* suppose some employee as HOD launched a leave application, and while it was still processing, his tenure got over and new HOD was made, now this HOD should be able to launch new leave application */
	/* never delete cc_faculty or hod, otherwise applications will be deleted */
	launched_by_email VARCHAR (255) REFERENCES all_email(email) ON DELETE CASCADE NOT NULL,
	curr_holder_email VARCHAR (255) REFERENCES all_email(email) ON DELETE CASCADE NOT NULL,
	next_holder_email VARCHAR (255) REFERENCES all_email(email) ON DELETE CASCADE,
	borrow_leaves_from_next_year BOOLEAN NOT NULL,
	no_of_required_leaves INTEGER NOT NULL
);

CREATE TABLE approved_or_rejected_leave_application(
	app_id INTEGER PRIMARY KEY,
	is_approved BOOLEAN NOT NULL,
	launched_by_emp_id INTEGER REFERENCES employee(emp_id) NOT NULL,
	launched_by_email VARCHAR (255) REFERENCES all_email(email) NOT NULL,
	borrow_leaves_from_next_year BOOLEAN NOT NULL,
	no_of_required_leaves INTEGER NOT NULL
);

CREATE TABLE leave_application_status(
	app_id INTEGER PRIMARY KEY,
	is_approved_or_rejected BOOLEAN
);

CREATE TABLE application_detail(
	app_id INTEGER REFERENCES leave_application_status(app_id) NOT NULL,
	stage INTEGER NOT NULL,
	holder_emp_id INTEGER REFERENCES employee(emp_id) NOT NULL,
	holder_email VARCHAR (255) REFERENCES all_email(email) NOT NULL,
	comments TEXT,
	date_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
	PRIMARY KEY(app_id, stage)
);


/*-------------------------------------------------------------------------------------------------------------*/

CREATE TYPE holder_choices AS ENUM(
	'owner',
	'hod',
	'adfa',
	'dfa',
	'director',
	'approve_or_reject'
);

/* assumption - leave application paths never form a cycle */
/* Could have added staff_email from staff table as foreign key, but what about HOD then */
CREATE TABLE fac_leave_app_path(
	curr_holder holder_choices NOT NULL PRIMARY KEY,
	next_holder holder_choices NOT NULL UNIQUE
);

/* assumption - leave application paths never form a cycle */
CREATE TABLE hods_deans_leave_app_path(
	curr_holder holder_choices NOT NULL PRIMARY KEY,
	next_holder holder_choices NOT NULL UNIQUE
);

CREATE TABLE rem_leaves(
	emp_id INTEGER REFERENCES employee(emp_id) ON DELETE CASCADE NOT NULL,
	year INTEGER NOT NULL,
	rem_leaves_this_year INTEGER NOT NULL DEFAULT 20,
	PRIMARY KEY(emp_id, year)
);


/*-------------------------------------------------------------------------------------------------------------*/

/* assuming nobody asks for more than 40 leaves per year */
/* assuming atleast one person (except the owner) is involved in the process */
CREATE OR REPLACE PROCEDURE launch_new_leave_application(la_email VARCHAR (255), la_no_of_required_leaves INTEGER, la_comments TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
	la_which_table which_table_choices;
	la_curr_holder holder_choices;
	la_next_holder holder_choices;
	la_curr_holder_email VARCHAR (255);
	la_next_holder_email VARCHAR (255);
	la_emp_id INTEGER;
	la_rem_leaves_this_year INTEGER;
	la_borrow_leaves_from_next_year BOOLEAN := FALSE;
	la_extra_leaves_req_from_next_year INTEGER;
	la_app_id INTEGER;
BEGIN

	SELECT which_table INTO la_which_table FROM all_email WHERE email = la_email;

	IF la_which_table = 'fac' THEN

		SELECT fac_emp_id INTO la_emp_id FROM faculty WHERE fac_email = la_email;

		SELECT next_holder INTO la_curr_holder FROM fac_leave_app_path WHERE curr_holder = 'owner';
		SELECT next_holder INTO la_next_holder FROM fac_leave_app_path WHERE curr_holder = la_curr_holder;

	/* must be hod or cc_fac, both of which have same application path */
	ELSE

		IF la_which_table = 'hod' THEN
			SELECT fac_emp_id INTO la_emp_id FROM faculty, hod WHERE fac_email = hod_fac_email AND hod_post_email = la_email;
		ELSE
			SELECT cc_fac_emp_id INTO la_emp_id FROM cc_faculty WHERE cc_fac_post_email = la_email;
		END IF;

		SELECT next_holder INTO la_curr_holder FROM hods_deans_leave_app_path WHERE curr_holder = 'owner';
		SELECT next_holder INTO la_next_holder FROM hods_deans_leave_app_path WHERE curr_holder = la_curr_holder;

	END IF;

	IF la_curr_holder = 'hod' THEN
		SELECT hod_post_email INTO la_curr_holder_email FROM hod, faculty WHERE hod_fac_email = fac_email AND fac_dep_name = (SELECT fac_dep_name FROM faculty WHERE fac_email = la_email);
	/* if not hod, then must be cc_faculty, because atleast 1 person is involved in process */
	ELSE
		SELECT cc_fac_post_email INTO la_curr_holder_email FROM cc_faculty WHERE cc_fac_post::text = la_curr_holder::text;
	END IF;

	IF la_next_holder = 'hod' THEN
		SELECT hod_post_email INTO la_next_holder_email FROM hod, faculty WHERE hod_fac_email = fac_email AND fac_dep_name = (SELECT fac_dep_name FROM faculty WHERE fac_email = la_email);
	ELSIF la_next_holder = 'approve_or_reject' THEN
		la_next_holder_email := NULL;
	/* if neither hod or approve_or_reject, then must be cc_faculty */
	ELSE
		SELECT cc_fac_post_email INTO la_next_holder_email FROM cc_faculty WHERE cc_fac_post::text = la_next_holder::text;
	END IF;

	IF NOT EXISTS (SELECT FROM rem_leaves WHERE emp_id = la_emp_id AND year = DATE_PART('year', CURRENT_DATE)) THEN
		INSERT INTO rem_leaves (emp_id, year) VALUES (la_emp_id, DATE_PART('year', CURRENT_DATE));
	END IF;

	SELECT rem_leaves_this_year INTO la_rem_leaves_this_year FROM rem_leaves WHERE emp_id = la_emp_id AND year = DATE_PART('year', CURRENT_DATE);

	IF la_no_of_required_leaves > la_rem_leaves_this_year THEN
		la_borrow_leaves_from_next_year := TRUE;
	END IF;

	INSERT INTO curr_leave_application (launched_by_emp_id, launched_by_email, curr_holder_email, next_holder_email, borrow_leaves_from_next_year, no_of_required_leaves) VALUES (la_emp_id, la_email, la_curr_holder_email, la_next_holder_email, la_borrow_leaves_from_next_year, la_no_of_required_leaves);

	SELECT app_id INTO la_app_id FROM curr_leave_application WHERE launched_by_emp_id = la_emp_id;

	INSERT INTO leave_application_status (app_id, is_approved_or_rejected) VALUES (la_app_id, FALSE);

	INSERT INTO application_detail (app_id, stage, holder_emp_id, holder_email, comments) VALUES (la_app_id, 0, la_emp_id, la_email, la_comments);

	COMMIT;
END;
$$;


/*-------------------------------------------------------------------------------------------------------------*/

/* function to check if the user is authenticated to approve or reject, i.e. is he the last one in application path */
/* check this everytime since the last person will approve_or_reject, not forward */
/* note that at one time, leave application can only be with one person */
CREATE FUNCTION can_approve_or_reject(la_app_id INTEGER) RETURNS BOOLEAN AS $$
BEGIN
	IF (SELECT next_holder_email FROM curr_leave_application WHERE la_app_id = app_id) = NULL THEN
		RETURN TRUE;
	ELSE
		RETURN FALSE;
	END IF;
END; $$
LANGUAGE PLPGSQL;


/*-------------------------------------------------------------------------------------------------------------*/

/* don't call this procedure if can_approve_or_reject returns true */
CREATE PROCEDURE forward(la_app_id INTEGER, la_comments TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
	la_owner_which_table which_table_choices;
	la_owner_email VARCHAR (255);
	la_curr_holder_email VARCHAR (255);
	la_curr_holder_emp_id INTEGER;
	la_next_holder_email VARCHAR (255);
	la_next_holder holder_choices;
	la_next_to_next_holder_email VARCHAR (255);
	la_next_to_next_holder holder_choices;
BEGIN

	SELECT which_table INTO la_owner_which_table FROM all_email WHERE email = (SELECT launched_by_email FROM curr_leave_application WHERE app_id = la_app_id);
	SELECT launched_by_email INTO la_owner_email FROM curr_leave_application WHERE app_id = la_app_id;
	SELECT curr_holder_email INTO la_curr_holder_email FROM curr_leave_application WHERE app_id = la_app_id;
	SELECT next_holder_email INTO la_next_holder_email FROM curr_leave_application WHERE app_id = la_app_id;

	IF (SELECT which_table FROM all_email WHERE email = la_curr_holder_email) = 'fac' THEN
		SELECT fac_emp_id INTO la_curr_holder_emp_id FROM faculty WHERE fac_email = la_curr_holder_email;
	ELSIF (SELECT which_table FROM all_email WHERE email = la_curr_holder_email) = 'hod' THEN
		SELECT fac_emp_id INTO la_curr_holder_emp_id FROM faculty, hod WHERE fac_email = hod_fac_email AND hod_post_email = la_curr_holder_email;
	ELSE
		SELECT cc_fac_emp_id INTO la_curr_holder_emp_id FROM cc_faculty WHERE cc_fac_post_email = la_curr_holder_email;
	END IF;

	IF (SELECT which_table FROM all_email WHERE email = la_next_holder_email) = 'hod' THEN
		la_next_holder := 'hod';
	ELSE
		SELECT cc_fac_post::text INTO la_next_holder FROM cc_faculty WHERE cc_fac_post_email = la_next_holder_email;
	END IF;

	IF la_owner_which_table = 'fac' THEN
		SELECT next_holder INTO la_next_to_next_holder FROM fac_leave_app_path WHERE curr_holder = la_next_holder;
	/* must be hod or cc_fac, both of which have same application path */
	ELSE
		SELECT next_holder INTO la_next_to_next_holder FROM hods_deans_leave_app_path WHERE curr_holder = la_next_holder;
	END IF;

	IF la_next_to_next_holder = 'hod' THEN
		SELECT hod_post_email INTO la_next_to_next_holder_email FROM hod, faculty WHERE hod_fac_email = fac_email AND fac_dep_name = (SELECT fac_dep_name FROM faculty WHERE fac_email = la_owner_email);
	ELSIF la_next_to_next_holder = 'approve_or_reject' THEN
		la_next_to_next_holder_email := NULL;
	/* if neither hod or approve_or_reject, then must be cc_faculty */
	ELSE
		SELECT cc_fac_post_email INTO la_next_to_next_holder_email FROM cc_faculty WHERE cc_fac_post::text = la_next_to_next_holder::text;
	END IF;

	INSERT INTO application_detail (app_id, stage, holder_emp_id, holder_email, comments) VALUES (la_app_id, (SELECT MAX(stage) FROM application_detail WHERE app_id = la_app_id) + 1, la_curr_holder_emp_id, la_curr_holder_email, la_comments);

	UPDATE curr_leave_application SET curr_holder_email = next_holder_email WHERE app_id = la_app_id;
	UPDATE curr_leave_application SET next_holder_email = la_next_to_next_holder_email WHERE app_id = la_app_id;

	COMMIT;
END;
$$;


/*-------------------------------------------------------------------------------------------------------------*/

CREATE PROCEDURE approve_or_reject(la_app_id INTEGER, la_is_approved BOOLEAN, la_comments TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
	la_curr_holder_email VARCHAR (255);
	la_curr_holder_emp_id INTEGER;
	la_launched_by_emp_id INTEGER;
	la_launched_by_email VARCHAR (255);
	la_borrow_leaves_from_next_year BOOLEAN;
	la_no_of_required_leaves INTEGER;
	la_rem_leaves_this_year INTEGER;
	la_extra_leaves_req_from_next_year INTEGER;
BEGIN

	SELECT curr_holder_email INTO la_curr_holder_email FROM curr_leave_application WHERE app_id = la_app_id;
	SELECT launched_by_emp_id INTO la_launched_by_emp_id FROM curr_leave_application WHERE app_id = la_app_id;
	SELECT launched_by_email INTO la_launched_by_email FROM curr_leave_application WHERE app_id = la_app_id;
	SELECT borrow_leaves_from_next_year INTO la_borrow_leaves_from_next_year FROM curr_leave_application WHERE app_id = la_app_id;
	SELECT no_of_required_leaves INTO la_no_of_required_leaves FROM curr_leave_application WHERE app_id = la_app_id;

	IF (SELECT which_table FROM all_email WHERE email = la_curr_holder_email) = 'fac' THEN
		SELECT fac_emp_id INTO la_curr_holder_emp_id FROM faculty WHERE fac_email = la_curr_holder_email;
	ELSIF (SELECT which_table FROM all_email WHERE email = la_curr_holder_email) = 'hod' THEN
		SELECT fac_emp_id INTO la_curr_holder_emp_id FROM faculty, hod WHERE fac_email = hod_fac_email AND hod_post_email = la_curr_holder_email;
	ELSE
		SELECT cc_fac_emp_id INTO la_curr_holder_emp_id FROM cc_faculty WHERE cc_fac_post_email = la_curr_holder_email;
	END IF;

	/* no_matter approved or rejected, this table contains everything */
	INSERT INTO application_detail (app_id, stage, holder_emp_id, holder_email, comments) VALUES (la_app_id, (SELECT MAX(stage) FROM application_detail WHERE app_id = la_app_id) + 1, la_curr_holder_emp_id, la_curr_holder_email, la_comments);

	INSERT INTO approved_or_rejected_leave_application (app_id, is_approved, launched_by_emp_id, launched_by_email, borrow_leaves_from_next_year, no_of_required_leaves) VALUES (la_app_id, la_is_approved, la_launched_by_emp_id, la_launched_by_email, la_borrow_leaves_from_next_year, la_no_of_required_leaves);

	DELETE FROM curr_leave_application WHERE app_id = la_app_id;

	UPDATE leave_application_status SET is_approved_or_rejected = TRUE WHERE app_id = la_app_id;

	IF la_is_approved = TRUE THEN

		SELECT rem_leaves_this_year INTO la_rem_leaves_this_year FROM rem_leaves WHERE emp_id = la_launched_by_emp_id AND year = DATE_PART('year', CURRENT_DATE);

		IF la_borrow_leaves_from_next_year = TRUE THEN
			la_extra_leaves_req_from_next_year := la_no_of_required_leaves - la_rem_leaves_this_year;
			IF NOT EXISTS (SELECT FROM rem_leaves WHERE emp_id = la_launched_by_emp_id AND year = DATE_PART('year', CURRENT_DATE)+1) THEN
				INSERT INTO rem_leaves (emp_id, year) VALUES (la_launched_by_emp_id, DATE_PART('year', CURRENT_DATE)+1);
			END IF;
			UPDATE rem_leaves SET rem_leaves_this_year = rem_leaves_this_year - la_extra_leaves_req_from_next_year WHERE emp_id = la_launched_by_emp_id AND year = (DATE_PART('year', CURRENT_DATE)+1);
			UPDATE rem_leaves SET rem_leaves_this_year = 0 WHERE emp_id = la_launched_by_emp_id AND year = DATE_PART('year', CURRENT_DATE);
		ELSE
			UPDATE rem_leaves SET rem_leaves_this_year = rem_leaves_this_year - la_no_of_required_leaves WHERE emp_id = la_launched_by_emp_id AND year = DATE_PART('year', CURRENT_DATE);
		END IF;

	END IF;

	COMMIT;
END;
$$;


/*-------------------------------------------------------------------------------------------------------------*/

CREATE PROCEDURE send_back_to_owner_for_more_comments(la_app_id INTEGER, la_comments TEXT)
LANGUAGE plpgsql
AS $$
DECLARE
BEGIN
	COMMIT;
END;
$$;